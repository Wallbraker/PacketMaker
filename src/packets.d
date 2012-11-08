// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/license.d.
module packets;

import std.algorithm : find, sort, filter;
import std.conv : to;
import std.json : parseJSON, JSONValue, JSON_TYPE;
import std.ascii : isAlphaNum;
import std.string : toLower, toUpper, format;


/**
 * A constant value used for compares.
 */
class Constant
{
	enum Kind
	{
		Integer,
		Bool,
		Float,
	}

	Kind kind;

	union {
		bool boolean;
		float floating;
		long integer;
	}

	string str; ///< string value straight from JSON.
}

/**
 * A member of a packet.
 */
class Member
{
	enum Kind
	{
		Value,
		ValueArray,
		ValueAnon,
		StructArray,
		CondMembers,
	}

	Kind kind;

	string type; // must if kind == [Value, ValueArray, ValueAnon, ArrayStruct]
	string name; // must if kind == [Value, ValueArray, ArrayStruct]

	string lengthType; // optinal if kind == ValueArray
	string times; // optinal if kind == ValueArray, must if kind == ArrayStruct

	Member[] members; // must if kind == [CondMembers, ArrayStruct]

	string condCmp;
	string condField;
	Constant condValue;
}

/**
 * Packet.
 */
class Packet
{
	enum From
	{	
		Server,
		Client,
		Both,
	}

	ubyte id;
	From from;

	string listenerName; ///< Name of function on listener.
	string readFuncName; ///< Read function name.
	string writeFuncName; ///< Write function name.
	string structName; ///< The struct type name.

	Member[] members;

	string upperName; ///< Not really used outside of the parser.
	string lowerName; ///< Not really used outside of the parser.
}

/**
 * Collection of packets and policies.
 */
class PacketGroup
{
public:
	Packet[] allPackets;
	Packet[] clientPackets;
	Packet[] serverPackets;


	const string idStr = "id"; ///< Name used 

	const string indentStr = "\t";

	const string packetSufixStr = "Packet";

	const string packetNameStr = "packet"; ///< packet name in read/write functions.
	const string lengthSuffixStr = "Length"; ///< Suffix for looking up array lengths.

	const string socketNameStr = "ms";
	const string socketTypeStr = "MinecraftSocket";

	const string readFuncPrefixStr = "read";
	const string writeFuncPrefixStr = "write";

	const string listenerNameStr = "li";
	const string clientListenerTypeStr = "ClientListener";
	const string serverListenerTypeStr = "ServerListener";


	string[string] typeMap;
	string[string] typeArrayMap;
	string[string] readFuncs;
	string[string] readArrayFuncs;
	string[string] writeFuncs;
	string[string] writeArrayFuncs;


public:
	this(Packet[] allPackets, Packet[] clientPackets, Packet[] serverPackets)
	{
		this.allPackets = allPackets;
		this.clientPackets = clientPackets;
		this.serverPackets = serverPackets;

		applyPolicy();
	}

	void applyPolicy()
	{
		void names(Packet packet) {
			packet.listenerName = packet.lowerName;
			packet.structName = packet.upperName ~ packetSufixStr;
			packet.readFuncName = readFuncPrefixStr ~ packet.structName;
			packet.writeFuncName = writeFuncPrefixStr ~ packet.structName;
		}

		foreach(packet; allPackets)
			names(packet);

		typeMap = null;
		typeArrayMap = null;
		readFuncs = null;
		readArrayFuncs = null;
		writeFuncs = null;
		writeArrayFuncs = null;

		void addType(string j, string type, string arrayType,
		             string readFunc, string readArrayFunc,
		             string writeFunc, string writeArrayFunc)
		{
			if (type !is null) typeMap[j] = type;
			if (arrayType !is null) typeArrayMap[j] = arrayType;
			if (readFunc !is null) readFuncs[j] = readFunc;
			if (readArrayFunc !is null) readArrayFuncs[j] = readArrayFunc;
			if (writeFunc !is null) writeFuncs[j] = writeFunc;
			if (writeArrayFunc !is null) writeArrayFuncs[j] = writeArrayFunc;
		}

		auto pt = [
			"bool", "byte", "ubyte", "int", "uint",
			"short", "ushort", "long", "ulong",
			"float", "double"];

		foreach(t; pt) {
			// D types maps directly to the types in the JSON file.
			string caped = toUpper(t[0 .. 1]) ~ t[1 .. $];
			addType(t, t, t ~ "[]",
			        readFuncPrefixStr ~ caped, readFuncPrefixStr ~ caped ~ "Array",
			        writeFuncPrefixStr ~ caped, writeFuncPrefixStr ~ caped ~ "Array");
		}

		addType("string", "string", null,
		        readFuncPrefixStr ~ "USC", null,
		        writeFuncPrefixStr ~ "USC", null);
		addType("meta", "Meta*", "Meta*",
		        readFuncPrefixStr ~ "Meta", readFuncPrefixStr ~ "Meta" ~ "Array",
		        writeFuncPrefixStr ~ "Meta", writeFuncPrefixStr ~ "Meta" ~ "Array");
		addType("slot", "Slot*", "Slot*",
		        readFuncPrefixStr ~ "Slot", readFuncPrefixStr ~ "Slot" ~ "Array",
		        writeFuncPrefixStr ~ "Slot", writeFuncPrefixStr ~ "Slot" ~ "Array");
		addType("ChunkMeta", null, "ChunkMeta[]",
		        null, readFuncPrefixStr ~ "ChunkMeta" ~ "Array",
		        null, writeFuncPrefixStr ~ "ChunkMeta" ~ "Array");
	}
}
