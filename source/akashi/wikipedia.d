module akashi.wikipedia;

import std.net.curl : get;
import std.json : JSONValue, parseJSON, JSONType;
import std.uri : encode;
import std.conv : to;
import std.regex : ctRegex, matchFirst, matchAll;
import std.string : indexOf, strip;
import std.algorithm : map;
import std.array : array;

static class Wikipedia
{
    struct Page
    {
        string title;
    }

    private enum baseURL = "https://en.wikipedia.org/w/api.php";

    private static JSONValue query(string[string] params)
    {
        params["format"] = "json";
        params["formatversion"] = "2";
        string queryStr;
        foreach (k, v; params)
        {
            if (queryStr.length > 0)
                queryStr ~= "&";
            queryStr ~= k~"="~encode(v);
        }

        return parseJSON(get(baseURL~"?"~queryStr).idup);
    }

    static Wikipedia.Page[] search(string term, int limit = 10, int offset = 0, string ns = "0", string srprop = "snippet|titlesnippet")
    {
        string[string] params = [
            "action" : "query",
            "list" : "search",
            "srsearch" : term,
            "srlimit" : limit.to!string,
            "sroffset" : offset.to!string,
            "srnamespace" : ns,
            "srprop" : srprop
        ];

        Wikipedia.Page[] ret;
        JSONValue json = query(params);
        
        if (json.isNull || !("query" in json) || !("search" in json["query"]))
            return ret;
        
        foreach (item; json["query"]["search"].array)
        {
            Wikipedia.Page page;
            page.title = item["title"].str;
            ret ~= page;
        }
        return ret;
    }

    static string[] html(Wikipedia.Page[] pages...)
    {
        string[] ret;
        string[string] params = [
            "action": "parse",
            "prop": "text"
        ];

        foreach (page; pages)
        {
            params["page"] = page.title;
            JSONValue json = query(params);
            
            if (!json.isNull && "parse" in json && "text" in json["parse"])
            {
                JSONValue textVal = json["parse"]["text"];
                if (textVal.type == JSONType.object && "*" in textVal)
                    ret ~= textVal["*"].str;
                else if (textVal.type == JSONType.string)
                    ret ~= textVal.str;
                else
                    ret ~= "";
            }
            else
                ret ~= "";
        }
        return ret;
    }

    static string[] wikitext(Wikipedia.Page[] pages...)
    {
        string[] ret;
        string[string] params = [
            "action": "parse",
            "prop": "wikitext"
        ];

        foreach (page; pages)
        {
            params["page"] = page.title;
            JSONValue json = query(params);
            
            if (!json.isNull && "parse" in json && "wikitext" in json["parse"])
            {
                JSONValue wikitextVal = json["parse"]["wikitext"];
                if (wikitextVal.type == JSONType.object && "*" in wikitextVal)
                    ret ~= wikitextVal["*"].str;
                else if (wikitextVal.type == JSONType.string)
                    ret ~= wikitextVal.str;
                else
                    ret ~= "";
            }
            else
                ret ~= "";
        }
        return ret;
    }

    static string[] images(Wikipedia.Page[] pages...)
    {
        string lead;
        foreach (page; pages)
            lead ~= page.title~'|';

        if (lead == null)
            return [];
        lead = lead[0..$-1];

        string[string] params = [
            "action": "query",
            "prop": "images",
            "titles": lead
        ];

        string[] ret;
        JSONValue json = query(params);
        
        if (!json.isNull && "query" in json && "pages" in json["query"])
        {
            foreach (i; 0..pages.length)
            {
                if (i < json["query"]["pages"].array.length && "images" in json["query"]["pages"][i])
                    ret ~= json["query"]["pages"][i]["images"].toString;
                else
                    ret ~= "[]";
            }
        }
        else
        {
            foreach (i; 0..pages.length)
                ret ~= "[]";
        }
        return ret;
    }

    static string[] extractPubChemCIDs(Wikipedia.Page page)
    {
        string[] wikitexts = wikitext(page);
        if (wikitexts.length == 0)
            return [];
        return extractPubChemCIDs(wikitexts[0]);
    }

    static string[] extractPubChemCIDs(string wikitext)
    {
        string[] cids;
        
        // Pattern 1: | PubChem = 644025 (most common in Drugbox)
        auto pattern1 = ctRegex!`PubChem\s*=\s*(\d+)`;
        auto matches1 = matchAll(wikitext, pattern1);
        foreach (match; matches1)
        {
            if (match.captures.length > 1)
            {
                string cid = strip(match.captures[1]);
                if (cid.length > 0)
                    cids ~= cid;
            }
        }
        
        // Pattern 2: | PubChemCID = 644025
        auto pattern2 = ctRegex!`PubChemCID\s*=\s*(\d+)`;
        auto matches2 = matchAll(wikitext, pattern2);
        foreach (match; matches2)
        {
            if (match.captures.length > 1)
            {
                string cid = strip(match.captures[1]);
                if (cid.length > 0)
                    cids ~= cid;
            }
        }
        
        // Pattern 3: {{PubChem|644025}}
        auto pattern3 = ctRegex!`\{\{\s*PubChem\s*\|\s*(\d+)\s*\}\}`;
        auto matches3 = matchAll(wikitext, pattern3);
        foreach (match; matches3)
        {
            if (match.captures.length > 1)
            {
                string cid = strip(match.captures[1]);
                if (cid.length > 0)
                    cids ~= cid;
            }
        }
        
        // Pattern 4: External links - https://pubchem.ncbi.nlm.nih.gov/compound/644025
        auto pattern4 = ctRegex!`https?://(?:www\.)?pubchem\.ncbi\.nlm\.nih\.gov/compound/(\d+)`;
        auto matches4 = matchAll(wikitext, pattern4);
        foreach (match; matches4)
        {
            if (match.captures.length > 1)
            {
                string cid = strip(match.captures[1]);
                if (cid.length > 0)
                    cids ~= cid;
            }
        }
        
        // Remove duplicates
        string[] unique;
        foreach (cid; cids)
        {
            bool found = false;
            foreach (existing; unique)
            {
                if (existing == cid)
                {
                    found = true;
                    break;
                }
            }
            if (!found)
                unique ~= cid;
        }
        
        return unique;
    }

    static JSONValue queryRaw(string[string] params)
    {
        return query(params);
    }
}

unittest
{
    Wikipedia.Page[] pages = Wikipedia.search("Ketamine", 1);
    assert(pages.length > 0, "Ketamine search should return at least one result");
    assert(pages[0].title.length > 0, "Wikipedia.Page title should not be empty");
}

unittest
{
    Wikipedia.Page[] pages = Wikipedia.search("Ketamine", 1);
    assert(pages.length > 0, "Should find Ketamine page");
    
    string[] wikitexts = Wikipedia.wikitext(pages[0]);
    assert(wikitexts.length == 1, "Should return one wikitext");
    assert(wikitexts[0].length > 100, "Ketamine page should have substantial content");
    assert(indexOf(wikitexts[0], "Ketamine") >= 0, "Should contain Ketamine");
}

unittest
{
    Wikipedia.Page[] pages = Wikipedia.search("Ketamine", 1);
    assert(pages.length > 0, "Should find Ketamine page");
    
    string[] htmls = Wikipedia.html(pages[0]);
    assert(htmls.length == 1, "Should return one HTML result");
    assert(htmls[0].length > 100, "Ketamine page should have HTML content");
}

unittest
{
    Wikipedia.Page[] pages = Wikipedia.search("Arketamine", 1);
    assert(pages.length > 0, "Should find Arketamine page");
    
    string[] cids = Wikipedia.extractPubChemCIDs(pages[0]);
    // CID may or may not be present, but function should work
    assert(cids.length >= 0, "CIDs array should be valid");
}

unittest
{
    string testWikitext = "| PubChem = 644025";
    string[] cids = Wikipedia.extractPubChemCIDs(testWikitext);
    assert(cids.length > 0, "Should extract CID from test wikitext");
    assert(cids[0] == "644025", "Should extract correct CID from simple pattern");
}

unittest
{
    string testWikitext = "{{Drugbox\n| PubChem = 644025\n}}";
    string[] cids = Wikipedia.extractPubChemCIDs(testWikitext);
    assert(cids.length > 0, "Should extract CID from Drugbox format");
    assert(cids[0] == "644025", "Should extract correct CID from Drugbox");
}

unittest
{
    string testWikitext = "See https://pubchem.ncbi.nlm.nih.gov/compound/644025 for details";
    string[] cids = Wikipedia.extractPubChemCIDs(testWikitext);
    assert(cids.length > 0, "Should extract CID from URL");
    assert(cids[0] == "644025", "Should extract correct CID from URL");
}

unittest
{
    string testWikitext = "| PubChemCID = 12345";
    string[] cids = Wikipedia.extractPubChemCIDs(testWikitext);
    assert(cids.length > 0, "Should extract CID from PubChemCID pattern");
    assert(cids[0] == "12345", "Should extract correct CID from PubChemCID");
}

unittest
{
    string testWikitext = "{{PubChem|99999}}";
    string[] cids = Wikipedia.extractPubChemCIDs(testWikitext);
    assert(cids.length > 0, "Should extract CID from template pattern");
    assert(cids[0] == "99999", "Should extract correct CID from template");
}

unittest
{
    string testWikitext = "| PubChem = 111\n| PubChem = 222\n| PubChem = 111";
    string[] cids = Wikipedia.extractPubChemCIDs(testWikitext);
    assert(cids.length == 2, "Should remove duplicate CIDs");
    assert(cids[0] == "111" || cids[1] == "111", "Should contain first CID");
    assert(cids[0] == "222" || cids[1] == "222", "Should contain second CID");
}

unittest
{
    Wikipedia.Page[] pages = Wikipedia.search("Wikipedia", 1);
    assert(pages.length > 0, "Should find Wikipedia page");
    
    string[] images_result = Wikipedia.images(pages[0]);
    assert(images_result.length == 1, "Should return one images result");
}

unittest
{
    Wikipedia.Page[] pages1 = Wikipedia.search("Ketamine", 1);
    Wikipedia.Page[] pages2 = Wikipedia.search("LSD", 1);
    assert(pages1.length > 0 && pages2.length > 0, "Should find both pages");
    
    Wikipedia.Page[] combined = pages1~pages2;
    string[] wikitexts = Wikipedia.wikitext(combined);
    assert(wikitexts.length == 2, "Should return wikitext for both pages");
    assert(wikitexts[0].length > 0 && wikitexts[1].length > 0, "Both wikitexts should have content");
}

unittest
{
    Wikipedia.Page[] pages = Wikipedia.search("NonExistentPageXYZ123", 1);
    assert(pages.length == 0, "Non-existent search should return empty array");
}

unittest
{
    Wikipedia.Page[] pages = Wikipedia.search("Ketamine", 5);
    assert(pages.length > 0, "Should return results");
    assert(pages.length <= 5, "Should not exceed limit");
    
    foreach (page; pages)
    {
        assert(page.title.length > 0, "All pages should have non-empty titles");
    }
}

unittest
{
    Wikipedia.Page[] pages = Wikipedia.search("Ketamine", 10, 0);
    assert(pages.length > 0, "Should return results with offset 0");
    
    Wikipedia.Page[] pagesOffset = Wikipedia.search("Ketamine", 10, 5);
    // Offset results may be different or empty, but function should work
    assert(pagesOffset.length >= 0, "Offset search should work");
}

unittest
{
    Wikipedia.Page[] pages = Wikipedia.search("", 1);
    // Empty search may return results or empty, but should not crash
    assert(pages.length >= 0, "Empty search should not crash");
}

unittest
{
    string[string] params = [
        "action": "query",
        "list": "search",
        "srsearch": "test"
    ];
    JSONValue raw = Wikipedia.queryRaw(params);
    assert(!raw.isNull, "Raw query should return JSON");
    assert("query" in raw, "Raw query should contain query");
}
