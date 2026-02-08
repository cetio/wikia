// module wikia.wikipedia;

// import wikia.composer;
// import std.json : JSONValue, parseJSON, JSONType;
// import std.conv : to;
// import std.string : assumeUTF, strip;
// import std.regex;
// import std.algorithm : canFind;
// import wikia.page;

// class Wikipedia
// {
//     static Orchestrator orchestrator = Orchestrator("https://en.wikipedia.org/w", 200);

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
//         // TODO: Metadata should be parsed by source.
//         page.parseDosage();
//     }

//     static Page[] search(string term, int limit = 10, int offset = 0, string ns = "0")
//     {
//         Page[] pages;
//         JSONValue json = query([
//             "action": "query", "list": "search", "srsearch": term,
//             "srlimit": limit.to!string, "sroffset": offset.to!string,
//             "srnamespace": ns, "srprop": "snippet|titlesnippet"
//         ]);

//         if (json.type == JSONType.null_ || "query" !in json || "search" !in json["query"])
//             return pages;

//         foreach (JSONValue item; json["query"]["search"].array)
//             pages ~= new Page(item["title"].str, "wikipedia");
//         return pages;
//     }

//     static string[] extractCIDs(Page page)
//     {
//         string[] cids;
//         enum pubChemRe = ctRegex!`PubChem\s*=\s*(\d+)`;
//         foreach (match; matchAll(page.raw, pubChemRe))
//         {
//             string cid = strip(match[1]);
//             if (cid.length && !cids.canFind(cid))
//                 cids ~= cid;
//         }

//         enum pubChemCidRe = ctRegex!`PubChemCID\s*=\s*(\d+)`;
//         foreach (match; matchAll(page.raw, pubChemCidRe))
//         {
//             string cid = strip(match[1]);
//             if (cid.length && !cids.canFind(cid))
//                 cids ~= cid;
//         }

//         enum pubChemTemplateRe = ctRegex!`\{\{\s*PubChem\s*\|\s*(\d+)\s*\}\}`;
//         foreach (match; matchAll(page.raw, pubChemTemplateRe))
//         {
//             string cid = strip(match[1]);
//             if (cid.length && !cids.canFind(cid))
//                 cids ~= cid;
//         }

//         enum pubChemUrlRe = ctRegex!`https?://(?:www\.)?pubchem\.ncbi\.nlm\.nih\.gov/compound/(\d+)`;
//         foreach (match; matchAll(page.raw, pubChemUrlRe))
//         {
//             string cid = strip(match[1]);
//             if (cid.length && !cids.canFind(cid))
//                 cids ~= cid;
//         }
//         return cids;
//     }
// }
