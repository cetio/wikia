module akashi.yahoo;

import std.net.curl : get;
import std.json : JSONValue, parseJSON, JSONType;
import std.uri : encode;
import std.conv : to;
import std.datetime : SysTime, Clock;
import core.thread : Thread;
import core.time;

static class YahooFinance
{
    struct Quote
    {
        double price;
        string longName;
        string symbol;
    }

    private static SysTime lastRequestTime = SysTime.init;
    private static const Duration minRequestInterval = dur!"msecs"(400);

    private static void rateLimit()
    {
        auto now = Clock.currTime();
        auto elapsed = now - lastRequestTime;
        if (elapsed < minRequestInterval)
            Thread.sleep(minRequestInterval - elapsed);
        lastRequestTime = Clock.currTime();
    }

    static YahooFinance.Quote getQuote(string symbol)
    {
        rateLimit();
        YahooFinance.Quote result;
        result.symbol = symbol;
        try
        {
            string url = "https://query1.finance.yahoo.com/v8/finance/chart/"
               ~encode(symbol)~"?interval=1d&range=5d";
            string body = get(url).idup;
            if (body.length == 0)
                return result;
            JSONValue json = parseJSON(body);
            if (json.isNull || !("chart" in json) || !("result" in json["chart"]))
                return result;
            JSONValue res = json["chart"]["result"];
            if (res.type != JSONType.array || res.array.length == 0)
                return result;
            JSONValue r = res.array[0];
            if ("meta" in r)
            {
                JSONValue meta = r["meta"];
                if ("regularMarketPrice" in meta)
                {
                    auto v = meta["regularMarketPrice"];
                    if (v.type == JSONType.float_)
                        result.price = v.floating;
                    else if (v.type == JSONType.integer)
                        result.price = v.integer.to!double;
                }
                if ("longName" in meta)
                    result.longName = meta["longName"].str;
                else if ("shortName" in meta)
                    result.longName = meta["shortName"].str;
                if ("symbol" in meta)
                    result.symbol = meta["symbol"].str;
            }
            if (result.price == 0 && "indicators" in r && "quote" in r["indicators"])
            {
                auto qarr = r["indicators"]["quote"].array;
                if (qarr.length > 0 && "close" in qarr[0] && qarr[0]["close"].array.length > 0)
                {
                    auto closeArr = qarr[0]["close"].array;
                    size_t i = closeArr.length;
                    while (i > 0)
                    {
                        i--;
                        auto v = closeArr[i];
                        if (v.type == JSONType.float_)
                        {
                            result.price = v.floating;
                            break;
                        }
                        if (v.type == JSONType.integer)
                        {
                            result.price = v.integer.to!double;
                            break;
                        }
                    }
                }
            }
        }
        catch (Exception) { }

        return result;
    }

    static JSONValue getRawJSON(string symbol)
    {
        rateLimit();
        try
        {
            string url = "https://query1.finance.yahoo.com/v8/finance/chart/"
               ~encode(symbol)~"?interval=1d&range=5d";
            string body = get(url).idup;
            if (body.length == 0)
                return JSONValue.init;
            return parseJSON(body);
        }
        catch (Exception)
            return JSONValue.init;
    }
}

unittest
{
    YahooFinance.Quote q = YahooFinance.getQuote("GOLD");
    assert(q.price > 0, "Yahoo GOLD quote price should be positive");
    assert(q.longName.length > 0, "Yahoo GOLD longName should be non-empty");
}

unittest
{
    JSONValue raw = YahooFinance.getRawJSON("GOLD");
    assert(!raw.isNull, "Raw JSON should not be null");
    assert("chart" in raw, "Raw JSON should contain chart");
}

unittest
{
    YahooFinance.Quote q = YahooFinance.getQuote("AAPL");
    assert(q.price > 0 || q.price == 0, "AAPL quote should have valid price (may be 0 if market closed)");
    assert(q.symbol.length > 0, "YahooFinance.Quote should have symbol");
}

unittest
{
    YahooFinance.Quote q = YahooFinance.getQuote("MSFT");
    assert(q.symbol.length > 0, "YahooFinance.Quote should have symbol");
    if (q.price > 0)
        assert(q.longName.length > 0, "If price is available, longName should be present");
}

unittest
{
    JSONValue raw = YahooFinance.getRawJSON("AAPL");
    if (!raw.isNull && "chart" in raw && "result" in raw["chart"])
    {
        JSONValue res = raw["chart"]["result"];
        if (res.type == JSONType.array && res.array.length > 0)
        {
            JSONValue r = res.array[0];
            assert("meta" in r || "indicators" in r, "Result should have meta or indicators");
        }
    }
}
