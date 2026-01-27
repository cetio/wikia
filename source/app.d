import akashi.wikipedia;
import akashi.entrez;
//import intuit;
//import intuit.response.embedding;

import std.stdio;
import std.json;
import std.array;
import std.regex;
import std.algorithm;
import std.string;
import std.uni : isWhite;
import std.math : sqrt;
import core.sys.posix.termios;
import core.sys.posix.unistd;
import std.datetime.stopwatch;
import std.getopt;
import std.conv : to;

string[] chunkize(string str, size_t tokens = 512, size_t stride = 128)
{
    tokens = cast(size_t)(tokens * 1.3);
    string[] words = str.split!(x => x.isWhite());

    string[] ret;
    size_t offset;
    foreach (i; 0..(words.length / tokens))
    {
        size_t start = offset;
        offset += tokens;

        if (start >= stride)
            start -= stride;

        if (offset + stride < words.length)
            ret ~= words[start..(offset + stride)].join(" ");
        else
            ret ~= words[start..offset].join(" ");
    }

    if (offset >= stride)
        offset -= stride;

    ret ~= words[offset..$].join(" ");
    return ret;
}

void main()
{
    // OpenAI ep = new OpenAI("http://127.0.0.1:1234/");
    // string llm = "qwen/qwen3-4b-2507";
    // string embd = "text-embedding-qwen3-embedding-0.6b";
}