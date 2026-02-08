// module wikia.psychonaut;

// import std.json : JSONValue, parseJSON, JSONType;
// import std.conv : to;
// import std.string : assumeUTF, strip, split;
// import std.regex : matchAll, ctRegex;
// import std.algorithm : canFind;
// import std.array : replace;
// import std.stdio : writeln;
// import std.datetime : Clock, Duration;

// import wikia.composer;
// import wikia.page;
// import wikia.compound;
// import wikia.pubchem;

// class Psychonaut
// {
//     static Orchestrator orchestrator = Orchestrator("https://psychonautwiki.org/w", 200);

//     private static JSONValue query(string[string] params)
//     {
//         JSONValue json;
//         params["format"] = "json";
//         params["formatversion"] = "2";

//         orchestrator.rateLimit();
//         orchestrator.client.get(
//             orchestrator.buildURL("/api.php", params), 
//             (ubyte[] data) {
//                 json = parseJSON(data.assumeUTF);
//             }, 
//             null
//         );
//         return json;
//     }

//     static void getContent(Page page)
//     {
//         JSONValue json = query(["action": "parse", "prop": "wikitext", "page": page.title]);
//         if ("parse" !in json || "wikitext" !in json["parse"])
//             return;

//         JSONValue wikitext = json["parse"]["wikitext"];

//         if (wikitext.type == JSONType.object && "*" in wikitext)
//             page.raw = wikitext["*"].str;
//         else if (wikitext.type == JSONType.string)
//             page.raw = wikitext.str;

//         page.sections = parseSections(page.raw);
//         page.metadata = parseMetadata(page.raw);
//     }

//     static void parseDosage(Page page)
//     {
//         if (page.raw == null)
//             return;

//         JSONValue json = query(["action": "parse", "prop": "wikitext", "page": "Template:SubstanceBox/"~page.title]);
//         if ("parse" !in json || "wikitext" !in json["parse"])
//             return;

//         JSONValue wikitext = json["parse"]["wikitext"];
//         string raw;
//         if (wikitext.type == JSONType.object && "*" in wikitext)
//             raw = wikitext["*"].str;
//         else if (wikitext.type == JSONType.string)
//             raw = wikitext.str;

//         if (raw == null)
//             return;

//         enum roaRe = ctRegex!(`\|\s*(\w+)ROA_(Threshold|Light|Common|Strong|Heavy)\s*=\s*([^\n|]+)`);
//         JSONValue dosage;
//         foreach (m; matchAll(raw, roaRe))
//         {
//             if (m.captures.length < 4 || m.captures[3].strip == null)
//                 continue;

//             string route = m.captures[1];
//             string rank = m.captures[2];
//             string range = m.captures[3].strip;

//             enum semRe = ctRegex!(`\[\[[^\]:]+::([^\]]+)\]\]`);
//             foreach (sm; matchAll(range, semRe))
//             {
//                 if (sm.captures.length > 1)
//                     range = range.replace(sm.captures[0], sm.captures[1].strip);
//             }
//             range = range.strip;

//             if (!range.length)
//                 continue;

//             if (route !in dosage)
//                 dosage[route] = JSONValue.object;
//             dosage[route][rank] = range;
//         }

//         page.metadata.fields["dosage"] = dosage.toString;
//     }

//     static Page[] search(string term, int limit = 10)
//     {
//         JSONValue json = query([
//             "action": "query", "list": "search", "srsearch": term,
//             "srlimit": limit.to!string, "srnamespace": "0",
//             "srprop": "snippet|titlesnippet"
//         ]);

//         if ("query" !in json || "search" !in json["query"])
//             return [];

//         Page[] ret;
//         foreach (JSONValue res; json["query"]["search"].array)
//         {
//             ret ~= new Page(res["title"].str);
//             if (ret.length >= limit)
//                 break;
//         }
//         return ret;
//     }
// }
