module akashi.entrez.eutils;

import std.net.curl : get, post;
import std.json : JSONValue, parseJSON;
import std.uri : encode;
import std.conv : to;
import std.string : indexOf;
import std.array : join;
import std.datetime : Clock, SysTime, Duration, msecs;
import core.thread : Thread;

// Base URL for Entrez E-utilities
private const string entrez = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/";

// Rate limiting: minimum 333ms between requests (3 requests/second)
private const Duration minRequestInterval = msecs(333);
private SysTime lastRequestTime;

// Initialize lastRequestTime to current time minus interval to allow first request
shared static this()
{
    lastRequestTime = Clock.currTime() - minRequestInterval;
}

// Rate limiting function
private void rateLimit()
{
    SysTime now = Clock.currTime();
    Duration elapsed = now - lastRequestTime;
    
    if (elapsed < minRequestInterval)
    {
        Duration sleepTime = minRequestInterval - elapsed;
        Thread.sleep(sleepTime);
    }
    
    lastRequestTime = Clock.currTime();
}

// TimeFrame struct for date range searches
struct TimeFrame
{
    string from;
    string to;
    
    static TimeFrame init()
    {
        return TimeFrame();
    }
}

// ESearch: Search Entrez database
JSONValue esearch(string DB)(
    string term,
    int retmax = 20,
    int retstart = 0,
    bool usehistory = false,
    TimeFrame timeframe = TimeFrame.init,
    string apiKey = null
)
{
    rateLimit();
    
    string url = entrez~"esearch.fcgi?db="~DB~"&term="~encode(term)~
        "&retmax="~retmax.to!string~"&retstart="~retstart.to!string~"&retmode=json";
    
    if (usehistory)
        url ~= "&usehistory=y";
    
    if (timeframe.from.length > 0)
        url ~= "&mindate="~encode(timeframe.from);
    if (timeframe.to.length > 0)
        url ~= "&maxdate="~encode(timeframe.to);
    
    if (apiKey !is null && apiKey.length > 0)
        url ~= "&api_key="~encode(apiKey);
    
    return parseJSON(get(url).to!string);
}

// EFetch overload for single ID
auto efetch(string DB, string RETMODE = "json")(
    string id,
    string rettype = "abstract",
    string apiKey = null
)
{
    return efetch!(DB, RETMODE)([id], rettype, apiKey);
}

// EFetch overload for JSON return mode
auto efetch(string DB, string RETMODE = "json")(
    string[] ids,
    string rettype,
    string apiKey = null
)
{
    if (ids.length == 0)
        return "";

    rateLimit();

    string url = entrez~"efetch.fcgi?db="~DB~"&retmode="~RETMODE~"&rettype="~rettype;

    // Use POST for more than 200 IDs or if URL would be too long
    string idParam = ids.join(",");
    if (ids.length > 200 || idParam.length > 2000)
    {
        string postData = "db="~DB~"&retmode="~RETMODE~"&rettype="~rettype~"&id="~idParam;
        if (apiKey !is null && apiKey.length > 0)
            postData ~= "&api_key="~encode(apiKey);

        static if (RETMODE == "json")
            return parseJSON(post(entrez~"efetch.fcgi", postData).to!string);
        else
            return post(entrez~"efetch.fcgi", postData).to!string;
    }
    else
    {
        url ~= "&id="~idParam;
        if (apiKey !is null && apiKey.length > 0)
            url ~= "&api_key="~encode(apiKey);

        static if (RETMODE == "json")
            return parseJSON(get(url).to!string);
        else
            return get(url).to!string;
    }
}

// ELink: Link records between Entrez databases
JSONValue elink(string dbfrom, string dbto)(
    string id,
    TimeFrame timeframe = TimeFrame.init,
    string apiKey = null
)
{
    rateLimit();
    
    string url = entrez~"elink.fcgi?dbfrom="~dbfrom~"&db="~dbto~"&id="~id~"&retmode=json";
    
    if (timeframe.from.length > 0)
        url ~= "&mindate="~encode(timeframe.from);
    if (timeframe.to.length > 0)
        url ~= "&maxdate="~encode(timeframe.to);
    
    if (apiKey !is null && apiKey.length > 0)
        url ~= "&api_key="~encode(apiKey);
    
    return parseJSON(get(url).to!string);
}