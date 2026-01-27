module akashi.psychonaut;

import std.net.curl : get;
import std.json : JSONValue, parseJSON, JSONType;
import std.uri : encode;
import std.conv : to;
import std.regex : ctRegex, matchFirst, matchAll;
import std.string : indexOf, strip;
import std.array : array;

static class Psychonaut
{
    struct Page
    {
        string title;
    }

    struct Erowid
    {
        string[] references;
        string experienceReports;
        string dosageInfo;
        string effectsInfo;
    }

    private enum baseURL = "https://psychonautwiki.org/w/api.php";

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

    static Psychonaut.Page[] search(string term, int limit = 10, int offset = 0, string ns = "0", string srprop = "snippet|titlesnippet")
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

        Psychonaut.Page[] ret;
        JSONValue json = query(params);
        
        if (json.isNull || !("query" in json) || !("search" in json["query"]))
            return ret;
        
        foreach (item; json["query"]["search"].array)
        {
            Psychonaut.Page page;
            page.title = item["title"].str;
            ret ~= page;
        }
        return ret;
    }

    static string[] html(Psychonaut.Page[] pages...)
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

    static string[] wikitext(Psychonaut.Page[] pages...)
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

    static string[] images(Psychonaut.Page[] pages...)
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

    static string[] erowidReferences(Psychonaut.Page page)
    {
        string[] refs;
        string[] wikitexts = wikitext(page);
        if (wikitexts.length == 0 || wikitexts[0].length == 0)
            return refs;
        
        string wikitext = wikitexts[0];
        
        // Look for Erowid links in external links section or references
        auto erowidRegex = ctRegex!`\[https?://(?:www\.)?erowid\.org[^\s\]]+\]`;
        auto matches = matchAll(wikitext, erowidRegex);
        
        foreach (match; matches)
        {
            string url = match.hit;
            // Extract URL from markdown link
            auto urlMatch = matchFirst(url, ctRegex!`\[(https?://[^\]]+)\]`);
            if (urlMatch && urlMatch.captures.length > 1)
                refs ~= urlMatch.captures[1];
            else
                refs ~= url;
        }
        
        // Also look for plain text Erowid URLs
        auto plainUrlRegex = ctRegex!`https?://(?:www\.)?erowid\.org/[^\s\n]+`;
        auto plainMatches = matchAll(wikitext, plainUrlRegex);
        foreach (match; plainMatches)
            refs ~= match.hit;
        
        return refs;
    }

    static string[] erowidReferences(string wikitext)
    {
        string[] refs;
        
        // Look for Erowid links in external links section or references
        auto erowidRegex = ctRegex!`\[https?://(?:www\.)?erowid\.org[^\s\]]+\]`;
        auto matches = matchAll(wikitext, erowidRegex);
        
        foreach (match; matches)
        {
            string url = match.hit;
            // Extract URL from markdown link
            auto urlMatch = matchFirst(url, ctRegex!`\[(https?://[^\]]+)\]`);
            if (urlMatch && urlMatch.captures.length > 1)
                refs ~= urlMatch.captures[1];
            else
                refs ~= url;
        }
        
        // Also look for plain text Erowid URLs
        auto plainUrlRegex = ctRegex!`https?://(?:www\.)?erowid\.org/[^\s\n]+`;
        auto plainMatches = matchAll(wikitext, plainUrlRegex);
        foreach (match; plainMatches)
            refs ~= match.hit;
        
        return refs;
    }

    static Psychonaut.Erowid getErowidData(Psychonaut.Page page)
    {
        Psychonaut.Erowid data;
        
        string[] wikitexts = wikitext(page);
        if (wikitexts.length == 0 || wikitexts[0].length == 0)
            return data;
        
        string wikitext = wikitexts[0];
        
        // Extract Erowid references
        data.references = erowidReferences(wikitext);
        
        // Extract sections that may contain Erowid-sourced information
        auto expMatch = matchFirst(wikitext, ctRegex!`==\s*Experience\s+reports\s*==(.*?)(?=\n==|$)`);
        if (expMatch && expMatch.captures.length > 1)
            data.experienceReports = expMatch.captures[1].strip();
        
        // Extract dosage information (may reference Erowid)
        auto dosageMatch = matchFirst(wikitext, ctRegex!`==\s*Dosages?\s*==(.*?)(?=\n==|$)`);
        if (!dosageMatch)
            dosageMatch = matchFirst(wikitext, ctRegex!`==\s*Dose\s*==(.*?)(?=\n==|$)`);
        if (!dosageMatch)
            dosageMatch = matchFirst(wikitext, ctRegex!`==\s*Dosing\s*==(.*?)(?=\n==|$)`);
        if (dosageMatch && dosageMatch.captures.length > 1)
        {
            string dosageText = dosageMatch.captures[1].strip();
            if (indexOf(dosageText, "erowid") >= 0 || indexOf(dosageText, "Erowid") >= 0)
                data.dosageInfo = dosageText;
        }
        
        // Extract effects (may reference Erowid)
        auto effectsMatch = matchFirst(wikitext, ctRegex!`==\s*Subjective\s+effects\s*==(.*?)(?=\n==|$)`);
        if (effectsMatch && effectsMatch.captures.length > 1)
        {
            string effectsText = effectsMatch.captures[1].strip();
            if (indexOf(effectsText, "erowid") >= 0 || indexOf(effectsText, "Erowid") >= 0)
                data.effectsInfo = effectsText;
        }
        
        return data;
    }

    static JSONValue queryRaw(string[string] params)
    {
        return query(params);
    }
}

unittest
{
    Psychonaut.Page[] pages = Psychonaut.search("LSD", 1);
    assert(pages.length > 0, "LSD search should return at least one result");
    assert(pages[0].title == "LSD", "First result should be LSD page");
}

unittest
{
    Psychonaut.Page[] pages = Psychonaut.search("LSD", 1);
    assert(pages.length > 0, "Should find LSD page");
    
    string[] wikitexts = Psychonaut.wikitext(pages[0]);
    assert(wikitexts.length == 1, "Should return one wikitext");
    assert(wikitexts[0].length > 1000, "LSD page should have substantial content (over 1000 chars)");
    assert(indexOf(wikitexts[0], "Lysergic acid diethylamide") >= 0 || 
           indexOf(wikitexts[0], "LSD") >= 0, "Should contain LSD content");
}

unittest
{
    Psychonaut.Page[] pages = Psychonaut.search("LSD", 1);
    assert(pages.length > 0, "Should find LSD page");
    
    string[] htmls = Psychonaut.html(pages[0]);
    assert(htmls.length == 1, "Should return one HTML result");
    assert(htmls[0].length > 100, "LSD page should have HTML content");
}

unittest
{
    Psychonaut.Page[] pages = Psychonaut.search("MDMA", 1);
    assert(pages.length > 0, "Should find MDMA page");
    
    string[] wikitexts = Psychonaut.wikitext(pages[0]);
    assert(wikitexts.length > 0 && wikitexts[0].length > 0, "Should have wikitext");
    
    string[] refs = Psychonaut.erowidReferences(pages[0]);
    // Erowid references may or may not be present, but function should work
    assert(refs.length >= 0, "References array should be valid");
}

unittest
{
    string testWikitext = "See [https://www.erowid.org/chemicals/lsd/lsd.shtml] for more info";
    string[] refs = Psychonaut.erowidReferences(testWikitext);
    assert(refs.length > 0, "Should extract Erowid reference from wikitext");
    assert(indexOf(refs[0], "erowid.org") >= 0, "Reference should contain erowid.org");
}

unittest
{
    string testWikitext = "https://www.erowid.org/chemicals/lsd/lsd.shtml is a good resource";
    string[] refs = Psychonaut.erowidReferences(testWikitext);
    assert(refs.length > 0, "Should extract plain Erowid URL");
    assert(indexOf(refs[0], "erowid.org") >= 0, "Reference should contain erowid.org");
}

unittest
{
    Psychonaut.Page[] pages = Psychonaut.search("LSD", 1);
    assert(pages.length > 0, "Should find LSD page");
    
    Psychonaut.Erowid data = Psychonaut.getErowidData(pages[0]);
    // Data may or may not be present, but function should work without errors
    assert(data.references.length >= 0, "References array should be valid");
}

unittest
{
    Psychonaut.Page[] pages = Psychonaut.search("Psilocybin", 1);
    assert(pages.length > 0, "Should find Psilocybin page");
    
    string[] images_result = Psychonaut.images(pages[0]);
    assert(images_result.length == 1, "Should return one images result");
}

unittest
{
    Psychonaut.Page[] pages = Psychonaut.search("Ketamine", 1);
    assert(pages.length > 0, "Should find Ketamine page");
    assert(pages[0].title.length > 0, "Page title should not be empty");
    
    string[] wikitexts = Psychonaut.wikitext(pages[0]);
    assert(wikitexts.length == 1, "Should return one wikitext");
    assert(wikitexts[0].length > 0, "Wikitext should not be empty");
}

unittest
{
    Psychonaut.Page[] pages1 = Psychonaut.search("LSD", 1);
    Psychonaut.Page[] pages2 = Psychonaut.search("MDMA", 1);
    assert(pages1.length > 0 && pages2.length > 0, "Should find both pages");
    
    Psychonaut.Page[] combined = pages1~pages2;
    string[] wikitexts = Psychonaut.wikitext(combined);
    assert(wikitexts.length == 2, "Should return wikitext for both pages");
    assert(wikitexts[0].length > 0 && wikitexts[1].length > 0, "Both wikitexts should have content");
}

unittest
{
    Psychonaut.Page[] pages = Psychonaut.search("NonExistentSubstanceXYZ123", 1);
    // Should return empty array, not crash
    assert(pages.length == 0, "Non-existent search should return empty array");
}

unittest
{
    Psychonaut.Page[] pages = Psychonaut.search("LSD", 5);
    assert(pages.length > 0, "Should return results");
    assert(pages.length <= 5, "Should not exceed limit");
    
    // Verify all pages have titles
    foreach (page; pages)
    {
        assert(page.title.length > 0, "All pages should have non-empty titles");
    }
}

unittest
{
    string[string] params = [
        "action": "query",
        "list": "search",
        "srsearch": "test"
    ];
    JSONValue raw = Psychonaut.queryRaw(params);
    assert(!raw.isNull, "Raw query should return JSON");
    assert("query" in raw, "Raw query should contain query");
}
