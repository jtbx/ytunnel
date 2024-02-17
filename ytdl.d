/*
* ytdl.d: helper functions for downloading YouTube videos
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

module ytdl;

import std.algorithm : all, canFind, findSplitBefore, startsWith;
import std.exception : basicExceptionCtors, enforce;

/**
 * Exception thrown when failure of downloading or
 * converting YouTube media occurs.
 */
class YouTubeDownloadException : Exception
{
	mixin basicExceptionCtors;
}

/**
 * Returns true if the given string is
 * a valid YouTube video ID.
 */
bool
validYouTubeVideoID(in char[] id) @safe pure
{
	import std.ascii : letters, digits;

	string validCharacters = letters ~ digits ~ "-_";

	if (id.length != 11)
		return false;

	return all!(ch => validCharacters.canFind(ch))(id);
}

/**
 * Separates a YouTube video URL from its ID.
 * Works with youtube.com/watch?v= and youtu.be.
 * If the URL isn't detected to be a youtube.com/watch?v
 * URL or a youtu.be URL, the original URL is returned
 * (in case only the video ID is given).
 *
 * Example:
 *  separateYouTubeID("https://www.youtube.com/watch?v=H3inzGGFefg")
 *  -> "H3inzGGFefg"
 */
char[]
separateYouTubeID(in char[] url) @safe pure
{
	bool
	startsWithHTTPS(in char[] url, string mdl) @safe pure
	{
		return startsWith(url,
			"http://" ~ mdl,
			"https://" ~ mdl,
			"http://www." ~ mdl,
			"https://www." ~ mdl) != 0;
	}
	char[]
	stripURL(in char[] url, string prefix) @safe pure
	{
		import std.string : stripLeft;

		return url
			.stripLeft("http")
			.stripLeft("s")
			.stripLeft("://")
			.stripLeft("www.")
			.stripLeft(prefix)
			.findSplitBefore("?")[0]
			.dup();
	}

	return
	   (startsWithHTTPS(url, "youtu.be/") ?
			stripURL(url, "youtu.be/") :
		startsWithHTTPS(url, "youtube.com/watch?v=") ?
			stripURL(url, "youtube.com/watch?v=")
		: url).dup();
}

/**
 * Makes a request to youtube.com and returns
 * the given video ID's title as a string.
 */
string
youTubeVideoTitle(in char[] id) @trusted
in (validYouTubeVideoID(id), "Invalid video ID")
{
	import std.json     : parseJSON;
	import std.net.curl : get;

	return get(
		"https://www.youtube.com/oembed?format=json&url=http%3A//youtube.com/watch%3Fv%3D"
		~ id).parseJSON()["title"].str;
}

/**
 * Using yt-dlp, downloads the given YouTube video
 * identified by id into a temporary file, and converts
 * it using ffmpeg to the format indicated by the
 * extension of the file name dest.
 *
 * fmt is a string that describes the audio/video
 * format to output. A list of all possible options
 * is provided in the manual page under "FORMAT SELECTION",
 * or you can pass the -F flag to see specific formats
 * for a particular video. If fmt is null, uses the default
 * setting for yt-dlp (bestvideo*+bestaudio/best).
 *
 * After downloading is complete, the media will be
 * converted using ffmpeg into the file extension
 * specified by dest, e.g. a dest file of song.mp3
 * will convert the content into that of an mp3 format.
 *
 * Throws ProcessException if failure to start a process
 * (yt-dlp or ffmpeg) occurs, FileException if traversing
 * the current directory fails somehow, or YouTubeDownloadException
 * if one of the started processes returns a non-zero exit code.
 */
void
downloadYouTubeVideo(string id, scope const(char[]) fmt, string dest) @trusted
in (validYouTubeVideoID(id), "Invalid video ID")
{
	import std.file : dirEntries, remove, rename, DirEntry, SpanMode;

	string yTmp;

	void
	spawn(scope const(char[])[] args)
	{
		import std.conv    : to;
		import std.process : spawnProcess, wait;
		
		int status;

		status = spawnProcess(args).wait();

		enforce!YouTubeDownloadException(status == 0,
			args[0] ~ " failed with exit code " ~ status.to!string());
	}

	yTmp = id ~ ".ytmp";

	spawn(["yt-dlp", "-q",
		"-f", fmt == null ? "bestvideo*+bestaudio/best" : fmt,
		"-o", yTmp, "--", id]);

	/*
	 * yt-dlp can sometimes create output files with names that
	 * have an extra extension on the end; this code looks for
	 * a file (not a directory) that begins with the specified
	 * output file name, and renames it to the intended output
	 * file.
	 */
	foreach (DirEntry ent; dirEntries(".", yTmp ~ ".*", SpanMode.shallow)) {
		if (!ent.isDir && ent.isFile) {
			rename(ent.name, yTmp);
			break;
		}
	}

	spawn(["ffmpeg", "-hide_banner", "-loglevel", "error",
		"-y", "-i", yTmp, dest]);

	remove(yTmp);
}
