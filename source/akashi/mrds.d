module akashi.mrds;

import std.net.curl : get;
import std.json : JSONValue, parseJSON, JSONType;
import std.uri : encode;
import std.conv : to;
import std.string : strip, split, toUpper, toLower;
import std.array : array;
import std.algorithm : filter, map;
import std.datetime : SysTime, Clock;
import core.thread : Thread;
import core.time;

static class MRDS
{
    struct Deposit
    {
        long objectId;
        string depId;
        string siteName;
        string devStat;
        string codeList;
        string grade;
        double x = double.nan;
        double y = double.nan;
        JSONValue attributes;
    }

    private enum baseURL = "https://services.arcgis.com/v01gqwM5QqNysAAi/ArcGIS/rest/services/"
        ~"Mineral_Resources_Data_System_MRDS_Compact_Version/FeatureServer/0";

    private static SysTime lastRequestTime = SysTime.init;
    private static const Duration minRequestInterval = dur!"msecs"(1000);

    private static void rateLimit()
    {
        auto now = Clock.currTime();
        auto elapsed = now - lastRequestTime;
        if (elapsed < minRequestInterval)
            Thread.sleep(minRequestInterval - elapsed);
        lastRequestTime = Clock.currTime();
    }

    private static string commodityToCode(string commodity)
    {
        string c = toLower(strip(commodity));
        if (c == "gold")
            return "AU";
        if (c == "silver")
            return "AG";
        if (c == "copper")
            return "CU";
        if (c == "platinum")
            return "PT";
        if (c == "lead")
            return "PB";
        if (c == "zinc")
            return "ZN";
        if (commodity.length >= 2)
            return toUpper(commodity[0 .. 2]);
        return toUpper(commodity);
    }

    static MRDS.Deposit[] queryDeposits(string where = "1=1", string outFields = "*", int resultRecordCount = 100)
    {
        rateLimit();
        MRDS.Deposit[] result;
        try
        {
            string url = baseURL~"/query?where="~encode(where)
               ~"&outFields="~encode(outFields)
               ~"&resultRecordCount="~resultRecordCount.to!string
               ~"&f=json";
            string raw = get(url).idup;
            JSONValue json = parseJSON(raw);
            if (json.isNull || !("features" in json))
                return result;
            foreach (feat; json["features"].array)
            {
                MRDS.Deposit d;
                if ("attributes" in feat)
                {
                    JSONValue attr = feat["attributes"];
                    d.attributes = attr;
                    if ("OBJECTID" in attr)
                    {
                        auto v = attr["OBJECTID"];
                        if (v.type == JSONType.integer)
                            d.objectId = v.integer;
                    }
                    if ("DEP_ID" in attr)
                        d.depId = attr["DEP_ID"].str;
                    if ("SITE_NAME" in attr)
                        d.siteName = attr["SITE_NAME"].str;
                    if ("DEV_STAT" in attr)
                        d.devStat = attr["DEV_STAT"].str;
                    if ("CODE_LIST" in attr)
                        d.codeList = attr["CODE_LIST"].str;
                    if ("Grade" in attr)
                        d.grade = attr["Grade"].str;
                }
                if ("geometry" in feat && feat["geometry"].type == JSONType.object)
                {
                    if ("x" in feat["geometry"])
                    {
                        auto v = feat["geometry"]["x"];
                        if (v.type == JSONType.float_)
                            d.x = v.floating;
                        else if (v.type == JSONType.integer)
                            d.x = v.integer.to!double;
                    }
                    if ("y" in feat["geometry"])
                    {
                        auto v = feat["geometry"]["y"];
                        if (v.type == JSONType.float_)
                            d.y = v.floating;
                        else if (v.type == JSONType.integer)
                            d.y = v.integer.to!double;
                    }
                }
                result ~= d;
            }
        }
        catch (Exception)
        {
        }
        return result;
    }

    static MRDS.Deposit[] queryByCommodity(string commodity, int resultRecordCount = 100)
    {
        string code = commodityToCode(commodity);
        string where = "CODE_LIST LIKE '%"~code~"%'";
        return queryDeposits(where, "OBJECTID,DEP_ID,SITE_NAME,DEV_STAT,CODE_LIST,Grade", resultRecordCount);
    }

    static JSONValue queryRaw(string where = "1=1", string outFields = "*", int resultRecordCount = 100)
    {
        rateLimit();
        try
        {
            string url = baseURL~"/query?where="~encode(where)
               ~"&outFields="~encode(outFields)
               ~"&resultRecordCount="~resultRecordCount.to!string
               ~"&f=json";
            string raw = get(url).idup;
            return parseJSON(raw);
        }
        catch (Exception)
        {
            return JSONValue.init;
        }
    }

    static int veinOreCountPerDeposit(MRDS.Deposit d)
    {
        if (d.codeList.length == 0)
            return 0;
        string[] parts = d.codeList.split();
        return cast(int) parts.map!(s => strip(s)).filter!(s => s.length > 0).array.length;
    }
}

unittest
{
    MRDS.Deposit[] deps = MRDS.queryByCommodity("gold", 10);
    assert(deps.length > 0, "MRDS queryByCommodity(gold) should return deposits");
}

unittest
{
    MRDS.Deposit[] deps = MRDS.queryDeposits("1=1", "DEP_ID,CODE_LIST,SITE_NAME", 5);
    assert(deps.length > 0, "MRDS queryDeposits should return features");
    bool hasCode = false;
    foreach (d; deps)
    {
        if (d.codeList.length > 0 || d.siteName.length > 0)
        {
            hasCode = true;
            break;
        }
    }
    assert(hasCode, "At least one feature should have CODE_LIST or SITE_NAME");
}

unittest
{
    MRDS.Deposit d;
    d.codeList = " CU AU AG";
    assert(MRDS.veinOreCountPerDeposit(d) == 3, "veinOreCountPerDeposit should count 3 from CODE_LIST");
}

unittest
{
    MRDS.Deposit[] deps = MRDS.queryByCommodity("silver", 5);
    assert(deps.length > 0, "MRDS queryByCommodity(silver) should return deposits");
    foreach (d; deps)
    {
        assert(d.codeList.length > 0 || d.siteName.length > 0, "MRDS.Deposit should have codeList or siteName");
    }
}

unittest
{
    MRDS.Deposit[] deps = MRDS.queryByCommodity("copper", 5);
    assert(deps.length > 0, "MRDS queryByCommodity(copper) should return deposits");
}

unittest
{
    JSONValue raw = MRDS.queryRaw("1=1", "OBJECTID", 1);
    assert(!raw.isNull, "Raw query should return JSON");
    if ("features" in raw)
        assert(raw["features"].type == JSONType.array, "Features should be an array");
}

unittest
{
    MRDS.Deposit[] deps = MRDS.queryDeposits("1=1", "OBJECTID,DEP_ID,SITE_NAME,CODE_LIST", 10);
    assert(deps.length > 0, "Should return deposits");
    foreach (d; deps)
    {
        assert(d.objectId > 0 || d.depId.length > 0, "MRDS.Deposit should have objectId or depId");
    }
}

unittest
{
    MRDS.Deposit[] deps = MRDS.queryDeposits("1=1", "*", 5);
    assert(deps.length > 0, "Should return deposits with all fields");
    bool hasCoordinates = false;
    foreach (d; deps)
    {
        if (!d.x.isNaN && !d.y.isNaN)
        {
            hasCoordinates = true;
            break;
        }
    }
    assert(hasCoordinates, "At least one deposit should have coordinates");
}
