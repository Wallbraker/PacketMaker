// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/license.d.
module parser;

import std.algorithm : find, sort, filter;
import std.conv : to;
import std.json : parseJSON, JSONValue, JSON_TYPE;
import std.ascii : isAlphaNum;
import std.string : toLower, toUpper, format;

import packets : Constant, Member, Packet;


/**
 * The main parser.
 */
class PacketParser
{
public:
	Packet[] serverPackets;
	Packet[] clientPackets;


public:
	void parse(string text)
	{
		serverPackets = null;
		clientPackets = null;

		auto root = parseJSON(text);

		foreach(key; root.object.keys) {
			if (key == "meta")
				continue;

			auto id = to!ubyte(key, 16);
			auto p = root.object[key];

			parsePacket(id, p);
		}

		sort!("a.id < b.id")(serverPackets);
		sort!("a.id < b.id")(clientPackets);
	}


private:
	void parsePacket(ubyte id, ref JSONValue p)
	{
		auto pSource = p.object["source"];

		if (pSource.type != JSON_TYPE.STRING)
			throw new Exception("Expected string type in tag \"source\"");
		string source = pSource.str;

		// Need to parse packet twice because some are
		// different depending on source.
		if (source == "C" || source == "B")
			parsePacket(id, p, "C");
		if (source == "S" || source == "B")
			parsePacket(id, p, "S");
	}

	void parsePacket(ubyte id, ref JSONValue p, string source)
	{
		auto pName = p.object["name"];

		if (pName.type != JSON_TYPE.STRING)
			throw new Exception("Expected string type in tag \"name\"");

		/*
		 * Identifiers
		 */
		string name;
		foreach(c; pName.str) {
			if (!isAlphaNum(c))
				continue;
			name ~= c;
		}
		string lowerName = toLower(name[0 .. 1]) ~ name[1 .. $];
		string upperName = toUpper(name[0 .. 1]) ~ name[1 .. $];

		/*
		 * From client or server.
		 */
		Packet.From from;
		if (source == "C")
			from = Packet.From.Client;
		else if (source == "S")
			from = Packet.From.Server;
		else
			throw new Exception("Invalid source attribute");

		/*
		 * Members
		 */
		auto st = p.object["structure"];
		if (st.type == JSON_TYPE.OBJECT) {
			string str = from == Packet.From.Server ? "S" : "C";
			st = st.object[str];
		}
		if (st.type != JSON_TYPE.ARRAY)
			throw new Exception("Invalid type of tag structure");

		Member[] m;
		foreach(member; st.array) {
			m ~= parseMember(member);
		}

		/*
		 * Do the creation.
		 */
		auto packet = new Packet();
		packet.id = id;
		packet.upperName = upperName;
		packet.lowerName = lowerName;
		packet.from = from;
		packet.members = m;

		if (from == Packet.From.Server) {
			serverPackets ~= packet;
		} else {
			clientPackets ~= packet;
		}
	}

	Member parseMember(ref JSONValue v)
	{
		auto m = new Member();

		m.kind = classifyMember(v);
		final switch(m.kind) with(Member.Kind) {
		case Value:
			m.type = v.array[0].str;
			m.name = v.array[1].str;
			break;
		case ValueAnon:
			m.type = v.array[0].str;
			break;
		case CondMembers:
			if (v.array[0].type == JSON_TYPE.ARRAY) {
				foreach(subMember; v.array[0].array)
					m.members ~= parseMember(subMember);
			} else {
				auto sub = new Member();
				sub.type = v.array[0].str;
				sub.name = v.array[1].str;
				if (sub.name.length > 0)
					sub.kind = Value;
				else
					sub.kind = ValueAnon;
				m.members = [sub];
			}
			auto c = v.array[2].object["condition"].object;
			m.condField = c["field"].str;
			m.condCmp = c["compare"].str;
			m.condValue = parseConstant(c["value"]);
			break;
		case StructArray:
			m.name = v.array[1].str;
			m.type = toUpper(m.name[0 .. 1]) ~ m.name[1 .. $];
			foreach(subMember; v.array[0].array)
				m.members ~= parseMember(subMember);
			m.times = v.array[2].object["times"].str;
		}

		return m;
	}

	Constant parseConstant(const ref JSONValue v)
	{
		auto ret = new Constant();

		switch(v.type) with (JSON_TYPE) {
		case INTEGER:
			ret.kind = Constant.Kind.Integer;
			ret.integer = v.integer;
			break;
		case FLOAT:
			ret.kind = Constant.Kind.Float;
			ret.floating = v.floating;
			break;
		case TRUE:
			ret.kind = Constant.Kind.Bool;
			ret.boolean = true;
			break;
		case FALSE:
			ret.kind = Constant.Kind.Bool;
			ret.boolean = false;
			break;
		default:
			throw new Exception("Can not turn into constant");
		}

		return ret;
	}

	Member.Kind classifyMember(const ref JSONValue v)
	{
		if (v.type != JSON_TYPE.ARRAY)
			throw new Exception("Type is not an array");

		auto arr = v.array;

		if (arr.length == 2) {
			if (arr[0].type != JSON_TYPE.STRING)
				throw new Exception("First element in 2 element type must be string");
			if (arr[1].type != JSON_TYPE.STRING)
				throw new Exception("Second element in 2 element type must be string");

			auto type = arr[0].str;
			auto name = arr[1].str;
			if (name.length > 0)
				return Member.Kind.Value;
			else
				return Member.Kind.ValueAnon;
		}

		if (arr.length == 3) {
			if (arr[1].type != JSON_TYPE.STRING)
				throw new Exception("Second element in 3 element type must be string");
			if (arr[2].type != JSON_TYPE.OBJECT)
				throw new Exception("Third element in 3 element type must be object");

			auto value = arr[0];
			auto name = arr[1].str;
			auto object = arr[2];

			if (value.type == JSON_TYPE.STRING) {
				bool used;
				if (hasCondition(object))
					return Member.Kind.CondMembers;

				if (hasTimes(object))
					throw new Exception("Values can't have times tags");

				if (hasUsed(object, used) && !used)
					return Member.Kind.ValueAnon;

				if (name.length > 0)
					return Member.Kind.Value;

				throw new Exception("Anon values can't be unused");
			}

			if (value.type == JSON_TYPE.ARRAY) {
				bool used;
				if (hasUsed(object, used))
					throw new Exception("Array types can't have used tags");

				if (name.length > 0) {
					if (!hasTimes(object))
						throw new Exception("ArrayStruct doesn't have a times tag");
					return Member.Kind.StructArray;
				} else {
					if (!hasCondition(object))
						throw new Exception("AnonStructs must have a condition tag");
					return Member.Kind.CondMembers;
				}
			}

			throw new Exception("First element in 3 element type must be string or array");
		}

		throw new Exception("Type array has wrong number of elements");
	}

	bool hasTimes(const ref JSONValue v)
	{
		if (("times" in v.object) is null)
			return false;

		auto times = v.object["times"];
		if (times.type != JSON_TYPE.STRING)
			throw new Exception("times object must be string");

		return true;
	}

	bool hasCondition(const ref JSONValue v)
	{
		if (v.type != JSON_TYPE.OBJECT)
			return false;

		if (("condition" in v.object) is null)
			return false;

		auto cond = v.object["condition"];
		if ("field" in cond.object &&
		    "compare" in cond.object &&
		    "value" in cond.object &&
		    cond.object["field"].type == JSON_TYPE.STRING &&
		    cond.object["compare"].type == JSON_TYPE.STRING)
			return true;

		throw new Exception("Invalid condition tag");
	}

	bool hasUsed(const ref JSONValue v, out bool value)
	{
		if (v.type != JSON_TYPE.OBJECT)
			return false;

		if (("used" in v.object) is null)
			return false;

		auto boolean = v.object["used"];
		if (boolean.type == JSON_TYPE.TRUE) {
			value = true;
			return true;
		} else if (boolean.type == JSON_TYPE.FALSE) {
			value = false;
			return true;
		}

		throw new Exception("Invalid used tag");
	}
}
