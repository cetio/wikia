module akashi.kitco;

import std.net.curl : get;
import std.json : JSONValue, parseJSON, JSONType;
import std.conv : to;
import std.string : indexOf;
import std.datetime : SysTime, Clock;
import core.thread : Thread;
import core.time;

private enum kitcoUrl = "https://www.kitco.com/price/precious-metals";

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

struct PreciousMetalsSpot
{
    double gold;
    double silver;
    double platinum;
    double palladium = double.nan;
}

private double extractMid(JSONValue j)
{
    if (j.isNull) return double.nan;
    if (j.type == JSONType.float_) return j.floating;
    if (j.type == JSONType.integer) return j.integer.to!double;
    if (j.type == JSONType.string && j.str.length > 0) return j.str.to!double;
    return double.nan;
}

PreciousMetalsSpot getPreciousMetalsSpot()
{
    rateLimit();
    PreciousMetalsSpot result;
    try
    {
        string html = get(kitcoUrl).idup;
        auto idx = indexOf(html, "type=\"application/json\">");
        if (idx < 0) return result;
        size_t jsonStart = idx + 24;
        while (jsonStart < html.length && (html[jsonStart] == ' ' || html[jsonStart] == '\t' || html[jsonStart] == '\n' || html[jsonStart] == '\r'))
            jsonStart++;
        if (jsonStart >= html.length || html[jsonStart] != '{') return result;
        auto endTag = indexOf(html, "</script>", cast(size_t)jsonStart);
        if (endTag < 0) return result;
        string jsonStr = html[jsonStart .. endTag];
        JSONValue root = parseJSON(jsonStr);
        if (root.isNull || !("props" in root) || !("pageProps" in root["props"])
            || !("dehydratedState" in root["props"]["pageProps"]))
            return result;
        JSONValue qs = root["props"]["pageProps"]["dehydratedState"]["queries"];
        if (qs.type != JSONType.array) return result;
        foreach (q; qs.array)
        {
            if (q.isNull || !("state" in q) || !("data" in q["state"])) continue;
            JSONValue data = q["state"]["data"];
            if (!("gold" in data)) continue;
            if ("gold" in data && "results" in data["gold"] && data["gold"]["results"].array.length > 0)
            {
                JSONValue r0 = data["gold"]["results"].array[0];
                if ("mid" in r0) result.gold = extractMid(r0["mid"]);
                else if ("bid" in r0) result.gold = extractMid(r0["bid"]);
            }
            if ("silver" in data && "results" in data["silver"] && data["silver"]["results"].array.length > 0)
            {
                JSONValue r0 = data["silver"]["results"].array[0];
                if ("mid" in r0) result.silver = extractMid(r0["mid"]);
                else if ("bid" in r0) result.silver = extractMid(r0["bid"]);
            }
            if ("platinum" in data && "results" in data["platinum"] && data["platinum"]["results"].array.length > 0)
            {
                JSONValue r0 = data["platinum"]["results"].array[0];
                if ("mid" in r0) result.platinum = extractMid(r0["mid"]);
                else if ("bid" in r0) result.platinum = extractMid(r0["bid"]);
            }
            if ("palladium" in data && "results" in data["palladium"] && data["palladium"]["results"].array.length > 0)
            {
                JSONValue r0 = data["palladium"]["results"].array[0];
                if ("mid" in r0) result.palladium = extractMid(r0["mid"]);
                else if ("bid" in r0) result.palladium = extractMid(r0["bid"]);
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

unittest
{
    PreciousMetalsSpot p = getPreciousMetalsSpot();
    assert(p.gold > 0, "Kitco gold should be positive");
    assert(p.silver > 0, "Kitco silver should be positive");
    assert(p.platinum > 0, "Kitco platinum should be positive");
}
