module wikia.page;

import std.array : join;
import std.algorithm : canFind, map;

import wikia.text.ast;
import wikia.text.wiki : parseWikitext;
import wikia.text.xml : parseXml;
import wikia.pubchem.compound : Compound;
import infer.config : config;

/// Lightweight section view derived from the AST, for backward compat.
struct Section
{
    string heading;
    string content;
    int level;
}

class Page
{
package:
    string _raw;
    Document _doc;
    bool _parsed;
    Section[] _sections;
    void delegate(Page) _fetchContent;

    this() { }

    this(
        string title,
        string source,
        string url,
        void delegate(Page) fetchContent
    )
    {
        this.title = title;
        this.source = source;
        this.url = url;
        this._fetchContent = fetchContent;
    }

public:
    string title;
    string source;
    string url;

    static Page fromRaw(string title, string source, string rawContent)
    {
        Page p = new Page();
        p.title = title;
        p.source = source;
        p._raw = rawContent;
        return p;
    }

    /// Access the raw source text, fetching lazily if needed.
    ref string raw()
    {
        if (_raw is null && _fetchContent !is null)
        {
            _fetchContent(this);
            _fetchContent = null;
        }
        return _raw;
    }

    /// The parsed AST Document. Lazily parsed on first access.
    /// Non-renderable node types (Templates, References, Comments,
    /// Categories, Images) are dropped after parsing.
    ref Document document()
    {
        if (!_parsed)
        {
            string r = raw;
            if (r !is null && r.length > 0)
            {
                if (source == "pubmed" || source == "pmc")
                    _doc = parseXml(r);
                else
                    _doc = parseWikitext(r);

                _doc.drop(Document.dropFlag(
                    NodeType.Template,
                    NodeType.Reference,
                    NodeType.Comment,
                    NodeType.Category,
                    NodeType.Image,
                ));
            }
            _parsed = true;
        }
        return _doc;
    }

    /// Flat section list derived from the AST (backward compat).
    Section[] sections()
    {
        if (_sections.length == 0)
        {
            Document doc = document();
            if (doc.nodes.length > 0)
                _sections = flattenSections(doc);
        }
        return _sections;
    }

    /// Full plain-text content.
    string fulltext()
    {
        Section[] secs = sections();
        if (secs.length == 0)
            return "";
        return secs.map!(s => s.content).join("\n\n");
    }

    /// Plain text of everything before the first section heading.
    string preamble()
    {
        Document doc = document();
        if (doc.nodes.length == 0)
            return "";
        return doc.preambleText();
    }
}

/// Resolve pages for a compound from all enabled sources.
Page[] resolvePage(Compound compound)
{
    Page[] ret;

    if (config.enabledSources.canFind("wikipedia"))
    {
        import wikia.wikipedia : resolvePage_ = resolvePage;
        Page page = resolvePage_(compound);
        if (page !is null)
            ret ~= page;
    }

    if (config.enabledSources.canFind("psychonaut"))
    {
        import wikia.psychonaut : resolvePage_ = resolvePage;
        Page page = resolvePage_(compound);
        if (page !is null)
            ret ~= page;
    }

    return ret;
}

/// Extract a flat Section[] from a Document AST.
private Section[] flattenSections(ref Document doc)
{
    Section[] ret;
    if (doc.nodes.length == 0)
        return ret;

    uint i = doc.nodes[0].childStart;
    while (i < doc.nodes[0].childEnd)
    {
        if (doc.nodes[i].type == NodeType.Section)
            collectSection(doc, doc.nodes[i], ret);
        i = doc.nextSiblingIdx(i);
    }
    return ret;
}

private void collectSection(ref Document doc, ref const Node sec, ref Section[] ret)
{
    string content = doc.extractText(sec);
    ret ~= Section(
        sec.text,
        content,
        cast(int) sec.level
    );
}