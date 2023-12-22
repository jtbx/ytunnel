/*
 * ytunnel: download content from YouTube in large batches
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

import std.ascii     : toLower;
import std.algorithm : findSplit, startsWith;
import std.conv      : to;
import std.exception : enforce;
import std.file      : chdir, exists, mkdirRecurse, read, write, FileException;
import std.format    : format;
import std.getopt    : getopt, GetOptException;
import std.path      : baseName, dirName, expandTilde;
import std.process   : environment, executeShell;
import std.stdio     : File, writeln, writefln;
import std.string    : lineSplitter, strip;

import ytdl;

struct MediaConfig
{
	string name, id;
}

enum VERSION = "0.0.0";

string fFlag;  /* register file */
string tFlag;  /* media type */
bool   VFlag;  /* show version */
bool   vFlag;  /* video */

File stderr;

version (OpenBSD) {
	immutable(char) *promises;
}

int
main(string[] args) @safe
{
	bool success;

	/* this evilness is required because I don't want to turn
	 * this into a whole new function just to use pledge() in
	 * a safe manner, or mark main() as @trusted */
	version (OpenBSD) () @trusted {
		import core.sys.openbsd.unistd : pledge;
		import std.string : toStringz;

		promises = toStringz("stdio rpath wpath cpath inet dns proc exec prot_exec");
		pledge(promises, null);
	}();

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
	string registerPath, homeDir;
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

	foreach (string prog; ["yt-dlp", "ffmpeg"]) {
		enforce(executeShell(">/dev/null 2>&1 command -v " ~ prog).status == 0,
			"cannot find " ~ prog);
	}
	
	homeDir = environment.get("HOME", null);
	enforce(homeDir, "cannot determine home directory; please set HOME");

	/* decide register path */
	registerPath = fFlag ? expandTilde(fFlag) :
		(environment.get("XDG_CONFIG_HOME", homeDir ~ "/.config")
			~ "/ytunnel/register");

	/* read whole file */
	try {
		register = registerPath.read().to!(char[]);
		chdir(args[1]);
	} catch (FileException e)
		throw new Exception(e.msg);

	parseRegister(register, registerPath, mconfs);
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
			throw new Exception(firstToLower(e.msg));
	}

	return true;
}

T
enforcef(T, A...)(T value, string msg, A args) @safe
{
	return enforce(value, msg.format(args));
}

string
firstToLower(in string s) @safe
{
	char[] s2;

	s2 = s.dup();
	s2[0] = toLower(s[0]);
	return s2.idup();
}

void
parseRegister(char[] register, string path, ref MediaConfig[] mconfs) @safe
{
	MediaConfig m;
	size_t lineno;

	lineno = 0;
	foreach (char[] line; register.lineSplitter()) {
		lineno++;
		line = line.strip();

		/* detect comment */
		if (line[0] == '#')
			continue;

		/* parse configuration line */
		auto result = line.findSplit(" ");
		m.id = separateYouTubeID(result[0]).strip();
		enforcef(validYouTubeVideoID(m.id), "%s:%d: invalid video ID: %s",
			path, lineno, m.id);
		m.name = result[1] == "" ?
			youTubeVideoTitle(m.id) : /* download video title and use it */
			result[2].strip().idup(); /* use the given title */

		mconfs.length++;
		mconfs[mconfs.length - 1] = m;
	}
}
