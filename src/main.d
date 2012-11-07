// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/license.d.
module main;

import std.file : read;

import parser;
import packets;
import generator;


int main(string[] args)
{
	auto pp = new PacketParser();
	string src = cast(string)read("packets.json");

	pp.parse(src);

	auto pg = new PacketGroup(pp.clientPackets, pp.serverPackets);
	output(pg);

	return 0;
}
