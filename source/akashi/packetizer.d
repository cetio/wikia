module akashi.packetizer;

import std.net.curl : get;
import std.json : JSONValue, parseJSON, JSONType;
import std.conv : to;
import std.math : isNaN;
import std.datetime : SysTime, Clock;
import core.thread : Thread;
import core.time;

static class Packetizer
{
    struct Spot
    {
        double gold;
        double silver;
        double platinum;
        string date;
    }

    private enum baseURL = "https://services.packetizer.com/spotprices/?f=json";

    private static SysTime lastRequestTime = SysTime.init;
    private static const Duration minRequestInterval = dur!"msecs"(500);

    private static void rateLimit()
    {
        SysTime now = Clock.currTime();
        Duration elapsed = now - lastRequestTime;
        if (elapsed < minRequestInterval)
            Thread.sleep(minRequestInterval - elapsed);
        lastRequestTime = Clock.currTime();
    }

    private static double extractPrice(JSONValue v)
    {
        if (v.type == JSONType.float_)
            return v.floating;
        else if (v.type == JSONType.integer)
            return v.integer.to!double;
        else if (v.type == JSONType.string && v.str.length > 0)
            return v.str.to!double;
        return double.nan;
    }

    static Packetizer.Spot getSpotPrices()
    {
        rateLimit();
        Packetizer.Spot result;
        string raw = get(baseURL).idup;
        JSONValue json = parseJSON(raw);
        if (json.isNull)
            return result;
        if ("gold" in json)
            result.gold = extractPrice(json["gold"]);
        if ("silver" in json)
            result.silver = extractPrice(json["silver"]);
        if ("platinum" in json)
            result.platinum = extractPrice(json["platinum"]);
        if ("date" in json)
            result.date = json["date"].str;
        return result;
    }

    static JSONValue getRawJSON()
    {
        rateLimit();
        try
        {
            string raw = get(baseURL).idup;
            return parseJSON(raw);
        }
        catch (Exception)
        {
            return JSONValue.init;
        }
    }
}

unittest
{
    Packetizer.Spot p = Packetizer.getSpotPrices();
    assert(p.gold > 0, "Packetizer gold should be positive");
    assert(p.silver > 0, "Packetizer silver should be positive");
    assert(p.platinum > 0, "Packetizer platinum should be positive");
    assert(p.date.length > 0, "Packetizer date should be non-empty");
}

unittest
{
    JSONValue raw = Packetizer.getRawJSON();
    assert(!raw.isNull, "Raw JSON should not be null");
    assert("gold" in raw, "Raw JSON should contain gold");
    assert("silver" in raw, "Raw JSON should contain silver");
    assert("platinum" in raw, "Raw JSON should contain platinum");
    assert("date" in raw, "Raw JSON should contain date");
}

unittest
{
    Packetizer.Spot p = Packetizer.getSpotPrices();
    assert(p.gold > 0 || p.gold.isNaN, "Gold should be positive or NaN");
    assert(p.silver > 0 || p.silver.isNaN, "Silver should be positive or NaN");
    assert(p.platinum > 0 || p.platinum.isNaN, "Platinum should be positive or NaN");
}

unittest
{
    JSONValue raw = Packetizer.getRawJSON();
    if (!raw.isNull)
    {
        if ("date" in raw)
        {
            assert(raw["date"].type == JSONType.string, "Date should be a string");
            assert(raw["date"].str.length > 0, "Date string should not be empty");
        }
    }
}
