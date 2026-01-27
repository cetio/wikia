module akashi.packetizer;

import std.net.curl : get;
import std.json : JSONValue, parseJSON, JSONType;
import std.conv : to;
import std.datetime : SysTime, Clock;
import core.thread : Thread;
import core.time;

private enum packetizerUrl = "https://services.packetizer.com/spotprices/?f=json";

private SysTime lastRequestTime = SysTime.init;
private const Duration minRequestInterval = dur!"msecs"(500);

private void rateLimit()
{
    auto now = Clock.currTime();
    auto elapsed = now - lastRequestTime;
    if (elapsed < minRequestInterval)
    {
        Thread.sleep(minRequestInterval - elapsed);
    }
    lastRequestTime = Clock.currTime();
}

struct SpotPrices
{
    double gold;
    double silver;
    double platinum;
    string date;
}

SpotPrices getSpotPrices()
{
    rateLimit();
    SpotPrices result;
    try
    {
        string raw = get(packetizerUrl).idup;
        JSONValue json = parseJSON(raw);
        if (json.isNull)
            return result;
        if ("gold" in json)
        {
            auto v = json["gold"];
            if (v.type == JSONType.float_) result.gold = v.floating;
            else if (v.type == JSONType.integer) result.gold = v.integer.to!double;
            else if (v.type == JSONType.string && v.str.length > 0) result.gold = v.str.to!double;
        }
        if ("silver" in json)
        {
            auto v = json["silver"];
            if (v.type == JSONType.float_) result.silver = v.floating;
            else if (v.type == JSONType.integer) result.silver = v.integer.to!double;
            else if (v.type == JSONType.string && v.str.length > 0) result.silver = v.str.to!double;
        }
        if ("platinum" in json)
        {
            auto v = json["platinum"];
            if (v.type == JSONType.float_) result.platinum = v.floating;
            else if (v.type == JSONType.integer) result.platinum = v.integer.to!double;
            else if (v.type == JSONType.string && v.str.length > 0) result.platinum = v.str.to!double;
        }
        if ("date" in json)
            result.date = json["date"].str;
    }
    catch (Exception)
    {
    }
    return result;
}

unittest
{
    SpotPrices p = getSpotPrices();
    assert(p.gold > 0, "Packetizer gold should be positive");
    assert(p.silver > 0, "Packetizer silver should be positive");
    assert(p.platinum > 0, "Packetizer platinum should be positive");
    assert(p.date.length > 0, "Packetizer date should be non-empty");
}
