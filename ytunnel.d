/*
 * ytunnel: download YouTube media in batch
 *
 * The GPLv2 License (GPLv2)
 * Copyright (c) 2023 Jeremy Baxter
 * 
 * ytunnel is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * 
 * ytunnel is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with ytunnel.  If not, see <http://www.gnu.org/licenses/>.
 */

module ytunnel;

import std.algorithm : findSplit, startsWith;
import std.conv      : to;
import std.exception : enforce;
import std.file   : chdir, exists, mkdirRecurse, read, write, FileException;
import std.format : format;
import std.getopt : getopt, GetOptException;
import std.path   : baseName, dirName, expandTilde;
import std.stdio  : File, writeln, writefln;
import std.string : lineSplitter, strip;
import std.typecons : Tuple;

import core.sys.posix.unistd : isatty;

import ytdl;

enum VERSION = "0.0.0";

string fFlag;  /* register file */
string tFlag;  /* media type */
bool   vFlag;  /* video */
bool   VFlag;  /* show version */

bool stdoutIsTTY;
File stderr;

struct MediaConfig
{
	string name;
	string id;
}

int
main(string[] args) @safe
{
	bool success;

	/* @safe way of opening stderr on Unix */
	stderr = File("/dev/stderr", "w");

	debug {
		return run(args) ? 0 : 1;
	}

	try {
		success = run(args);
	} catch (Exception e) {
		if (typeid(e) == typeid(Exception)) {
			stderr.writefln("%s: %s", baseName(args[0]), e.msg);
		} else {
			stderr.writefln("%s: uncaught %s in %s:%d: %s",
				baseName(args[0]),
				typeid(e).name,
				e.file, e.line, e.msg);
			stderr.writeln("this is an unexpected fatal error");
		}
		success = false;
	}

	return success ? 0 : 1;
}

bool
run(string[] args) @safe
{
	char[] register;
	string registerPath;
	MediaConfig[] mconfs;

	fFlag = null;
	tFlag = "flac";

	/* parse command-line options */
	try {
		import std.getopt : cf = config;

		getopt(args,
			cf.bundling, cf.caseSensitive,
			"f", &fFlag,
			"t", &tFlag,
			"V", &VFlag,
			"v", &vFlag
		);
	} catch (GetOptException e) {
		import std.regex : ctr = ctRegex, matchFirst;

		string opt = e.msg.matchFirst(ctr!("-."))[0];

		enforce(!e.msg.startsWith("Unrecognized option"),
			"unknown option " ~ opt);
		enforce(!e.msg.startsWith("Missing value for argument"),
			"missing argument for option " ~ opt);

		throw new Exception(e.msg); /* catch-all */
	}

	if (VFlag) {
		writeln("ytunnel version " ~ VERSION);
		return true;
	}
	
	if (args.length != 2) {
		stderr.writefln("usage: %s [-Vv] [-f register] [-t type]",
			baseName(args[0]));
		return false;
	}

	stdoutIsTTY = isatty(1) == 1 ? true : false;

	foreach (string prog; ["yt-dlp", "ffmpeg"]) {
		import std.process : executeShell;

		enforce(
			executeShell(
				format!"command -v %s >/dev/null 2>&1"(prog)
			).status == 0,
			format!"cannot find %s"(prog));
	}
	
	/* decide register path */
	registerPath = expandTilde(fFlag ? fFlag : "~/.config/ytunnel/register");
	mkdirRecurse(dirName(registerPath));
	
	if (!registerPath.exists())
		registerPath.write("");

	/* read whole file */
	register = registerPath.read().to!(char[]);

	try
		chdir(args[1]);
	catch (FileException e)
		throw new Exception(e.msg);

	foreach (char[] line; register.lineSplitter()) {
		MediaConfig m;

		/* parse configuration line */
		auto result = line.findSplit(" ");
		try {
			m.id = separateYouTubeID(result[0]).strip();
			m.name = result[1] == "" ?
				youTubeVideoTitle(m.id) : /* download video title and use it */
				result[2].strip().idup(); /* use the given custom title */
		} catch (YouTubeURLException e)
			throw new Exception(e.msg);

		mconfs.length++;
		mconfs[mconfs.length - 1] = m;
	}
	
	foreach (MediaConfig m; mconfs) {
		string dest;

		writefln("%s\t%s", m.id, m.name);
		dest = format!"%s.%s"(m.name, tFlag);

		/* if the file exists, skip */
		if (dest.exists())
			continue;
		/* do the download */
		try
			downloadYouTubeVideo(m.id, vFlag ? null : "bestaudio", dest);
		catch (YouTubeDownloadException e)
			throw new Exception(e.msg);
	}

	return true;
}
