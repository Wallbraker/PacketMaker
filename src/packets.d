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
	Packet[] clientPackets;
	Packet[] serverPackets;


	const string idStr = "id"; ///< Name used 

	const string packetNameStr = "packet"; ///< packet name in read/write functions.
	const string lengthSuffixStr = "Length"; ///< Suffix for looking up array lengths.

	const string socketNameStr = "ms";
	const string socketTypeStr = "MinecraftSocket";

	const string readFuncPrefixStr = "read";
	const string writeFuncPrefixStr = "write";

	const string listenerNameStr = "li";
	const string clientListenerTypeStr = "ClientListener";
	const string serverListenerTypeStr = "ServerListener";

	const string packetFromClientPrefixStr = "Client";
	const string packetFromServerPrefixStr = "Server";


public:
	this(Packet[] clientPackets, Packet[] serverPackets)
	{
		this.clientPackets = clientPackets;
		this.serverPackets = serverPackets;

		applyPolicy();
	}

	void applyPolicy()
	{
		void names(Packet packet) {
			packet.listenerName = packet.lowerName;
			packet.readFuncName = readFuncPrefixStr ~ packet.structName;
			packet.writeFuncName = writeFuncPrefixStr ~ packet.structName;
		}

		foreach(packet; serverPackets) {
			packet.structName = packetFromServerPrefixStr ~ packet.upperName;
			names(packet);
		}

		foreach(packet; clientPackets) {
			packet.structName = packetFromClientPrefixStr ~ packet.upperName;
			names(packet);
		}
	}
}
