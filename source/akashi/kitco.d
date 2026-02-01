module akashi.kitco;

import std.net.curl : get;
import std.json : JSONValue, parseJSON, JSONType;
import std.conv : to;
import std.string : indexOf;
import std.datetime : SysTime, Clock;
import core.thread : Thread;
import core.time;

static class Kitco
{
    struct Spot
    {
        double gold;
        double silver;
        double platinum;
        double palladium = double.nan;
    }

    private enum baseURL = "https://www.kitco.com/price/precious-metals";

    private static SysTime lastRequestTime = SysTime.init;
    private static const Duration minRequestInterval = dur!"msecs"(500);

    private static void rateLimit()
    {
        auto now = Clock.currTime();
        auto elapsed = now - lastRequestTime;
        if (elapsed < minRequestInterval)
            Thread.sleep(minRequestInterval - elapsed);
        lastRequestTime = Clock.currTime();
    }

    private static double extractMid(JSONValue j)
    {
        if (j.isNull)
            return double.nan;
        if (j.type == JSONType.float_)
            return j.floating;
        if (j.type == JSONType.integer)
            return j.integer.to!double;
        if (j.type == JSONType.string && j.str.length > 0)
            return j.str.to!double;
        return double.nan;
    }

    static Kitco.Spot getSpotPrices()
    {
        rateLimit();
        Kitco.Spot result;
        try
        {
            string html = get(baseURL).idup;
            auto idx = indexOf(html, "type=\"application/json\">");
            if (idx < 0)
                return result;
            size_t jsonStart = idx + 24;
            while (jsonStart < html.length && (html[jsonStart] == ' ' || html[jsonStart] == '\t' || html[jsonStart] == '\n' || html[jsonStart] == '\r'))
                jsonStart++;
            if (jsonStart >= html.length || html[jsonStart] != '{')
                return result;
            auto endTag = indexOf(html, "</script>", cast(size_t)jsonStart);
            if (endTag < 0)
                return result;
            string jsonStr = html[jsonStart .. endTag];
            JSONValue root = parseJSON(jsonStr);
            if (root.isNull || !("props" in root) || !("pageProps" in root["props"])
                || !("dehydratedState" in root["props"]["pageProps"]))
                return result;
            JSONValue qs = root["props"]["pageProps"]["dehydratedState"]["queries"];
            if (qs.type != JSONType.array)
                return result;
            foreach (q; qs.array)
            {
                if (q.isNull || !("state" in q) || !("data" in q["state"]))
                    continue;
                JSONValue data = q["state"]["data"];
                if (!("gold" in data))
                    continue;
                if ("gold" in data && "results" in data["gold"] && data["gold"]["results"].array.length > 0)
                {
                    JSONValue r0 = data["gold"]["results"].array[0];
                    if ("mid" in r0)
                        result.gold = extractMid(r0["mid"]);
                    else if ("bid" in r0)
                        result.gold = extractMid(r0["bid"]);
                }
                if ("silver" in data && "results" in data["silver"] && data["silver"]["results"].array.length > 0)
                {
                    JSONValue r0 = data["silver"]["results"].array[0];
                    if ("mid" in r0)
                        result.silver = extractMid(r0["mid"]);
                    else if ("bid" in r0)
                        result.silver = extractMid(r0["bid"]);
                }
                if ("platinum" in data && "results" in data["platinum"] && data["platinum"]["results"].array.length > 0)
                {
                    JSONValue r0 = data["platinum"]["results"].array[0];
                    if ("mid" in r0)
                        result.platinum = extractMid(r0["mid"]);
                    else if ("bid" in r0)
                        result.platinum = extractMid(r0["bid"]);
                }
                if ("palladium" in data && "results" in data["palladium"] && data["palladium"]["results"].array.length > 0)
                {
                    JSONValue r0 = data["palladium"]["results"].array[0];
                    if ("mid" in r0)
                        result.palladium = extractMid(r0["mid"]);
                    else if ("bid" in r0)
                        result.palladium = extractMid(r0["bid"]);
                }
                if (result.gold > 0 || result.silver > 0 || result.platinum > 0)
                    break;
            }
        }
        catch (Exception)
        {
        }
        return result;
    }

    static JSONValue getRawJSON()
    {
        rateLimit();
        try
        {
            string html = get(baseURL).idup;
            auto idx = indexOf(html, "type=\"application/json\">");
            if (idx < 0)
                return JSONValue.init;
            size_t jsonStart = idx + 24;
            while (jsonStart < html.length && (html[jsonStart] == ' ' || html[jsonStart] == '\t' || html[jsonStart] == '\n' || html[jsonStart] == '\r'))
                jsonStart++;
            if (jsonStart >= html.length || html[jsonStart] != '{')
                return JSONValue.init;
            auto endTag = indexOf(html, "</script>", cast(size_t)jsonStart);
            if (endTag < 0)
                return JSONValue.init;
            string jsonStr = html[jsonStart .. endTag];
            return parseJSON(jsonStr);
        }
        catch (Exception)
        {
            return JSONValue.init;
        }
    }
}

unittest
{
    Kitco.Spot p = Kitco.getSpotPrices();
    assert(p.gold > 0, "Kitco gold should be positive");
    assert(p.silver > 0, "Kitco silver should be positive");
    assert(p.platinum > 0, "Kitco platinum should be positive");
}

unittest
{
    JSONValue raw = Kitco.getRawJSON();
    assert(!raw.isNull, "Raw JSON should not be null");
    assert("props" in raw, "Raw JSON should contain props");
}

unittest
{
    Kitco.Spot p = Kitco.getSpotPrices();
    assert(p.gold > 0 || p.gold is double.nan, "Gold should be positive or NaN");
    assert(p.silver > 0 || p.silver is double.nan, "Silver should be positive or NaN");
    assert(p.platinum > 0 || p.platinum is double.nan, "Platinum should be positive or NaN");
    assert(p.palladium > 0 || p.palladium is double.nan, "Palladium should be positive or NaN");
}

unittest
{
    JSONValue raw = Kitco.getRawJSON();
    if (!raw.isNull && "props" in raw)
    {
        assert("pageProps" in raw["props"], "Should have pageProps in props");
    }
}
