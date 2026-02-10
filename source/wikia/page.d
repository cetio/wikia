module wikia.page;

import std.regex;
import std.string : strip;
import std.array : replace;

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
        auto p = new Page();
        p.title = title;
        p.source = source;
        p._raw = rawContent;
        return p;
    }

    ref string raw()
    {
        if (_raw is null && _fetchContent !is null)
        {
            _fetchContent(this);
            _fetchContent = null;
        }
        return _raw;
    }

    Section[] sections()
    {
        if (_sections.length == 0 && raw !is null)
            _sections = parseSections(_raw);

        return _sections;
    }

    string fulltext() const
    {
        import std.array : join;
        import std.algorithm : map;
        if (_sections.length == 0)
            return "";
        return _sections.map!(s => s.content).join("\n\n");
    }

    string preamble()
    {
        if (raw is null)
            return "";
        return parsePreamble(_raw);
    }
}

Section[] parseSections(string wikitext)
{
    Section[] ret;
    if (!wikitext.length)
        return ret;

    enum headingRe = ctRegex!(r"(={2,6})\s*([^=]+?)\s*\1");

    size_t lastEnd;
    string lastHeading;
    int lastLevel;
    foreach (match; matchAll(wikitext, headingRe))
    {
        size_t start = match.pre.length;
        int level = cast(int) match[1].length;
        string heading = match[2].strip;

        if (lastHeading.length)
            ret ~= Section(lastHeading,
                wikitext[lastEnd..start].strip, lastLevel);

        lastHeading = heading;
        lastLevel = level;
        lastEnd = start + match.hit.length;
    }

    if (lastHeading.length)
        ret ~= Section(lastHeading,
            wikitext[lastEnd..$].strip, lastLevel);

    return ret;
}

string parsePreamble(string wikitext)
{
    if (!wikitext.length)
        return "";

    enum headingRe = ctRegex!(r"(={2,6})\s*([^=]+?)\s*\1");
    auto m = matchFirst(wikitext, headingRe);
    if (m.empty)
        return cleanWikitext(wikitext.strip);

    string pre = wikitext[0..m.pre.length].strip;
    return pre.length > 0 ? cleanWikitext(pre) : "";
}

string cleanWikitext(string text)
{
    if (text is null || text.length == 0)
        return "";

    // Remove HTML comments
    enum commentRe = ctRegex!(`<!--[\s\S]*?-->`);
    foreach (m; matchAll(text, commentRe))
        text = text.replace(m.hit, "");

    // Remove <ref>...</ref> content tags (with content between them)
    enum refContentRe = ctRegex!(`<ref[^>]*>[\s\S]*?</ref>`);
    foreach (m; matchAll(text, refContentRe))
        text = text.replace(m.hit, "");

    // Remove self-closing and open/close ref tags
    enum refRe = ctRegex!(`</?ref[^>]*/?>`);
    foreach (m; matchAll(text, refRe))
        text = text.replace(m.hit, "");

    // Remove categories
    enum catRe = ctRegex!(`\[\[Category:[^\]]*\]\]`);
    foreach (m; matchAll(text, catRe))
        text = text.replace(m.hit, "");

    // Remove file/image links [[File:...]] [[Image:...]]
    enum fileRe = ctRegex!(`\[\[(?:File|Image):[^\]]*\]\]`);
    foreach (m; matchAll(text, fileRe))
        text = text.replace(m.hit, "");

    // Remove wikitables {| ... |}
    text = stripNested(text, "{|", "|}");

    // Remove templates {{ ... }} (nested)
    text = stripNested(text, "{{", "}}");

    // Convert wiki links [[target|display]] -> display, [[target]] -> target
    enum linkRe = ctRegex!(`\[\[([^\]|]+)(?:\|([^\]]+))?\]\]`);
    foreach (m; matchAll(text, linkRe))
    {
        string display = m[2].length > 0 ? m[2] : m[1];
        text = text.replace(m.hit, display);
    }

    // Remove remaining HTML tags
    enum htmlRe = ctRegex!(`<[^>]+>`);
    foreach (m; matchAll(text, htmlRe))
        text = text.replace(m.hit, "");

    // Remove bold/italic markup
    text = text.replace("'''''", "");
    text = text.replace("'''", "");
    text = text.replace("''", "");

    // Convert HTML entities
    text = text.replace("&nbsp;", " ");
    text = text.replace("&ndash;", "–");
    text = text.replace("&mdash;", "—");
    text = text.replace("&amp;", "&");
    text = text.replace("&lt;", "<");
    text = text.replace("&gt;", ">");

    // Convert bullet/numbered list markup to plain text
    enum listRe = ctRegex!(`(?m)^\*+\s*`);
    foreach (m; matchAll(text, listRe))
        text = text.replace(m.hit, "• ");

    enum numListRe = ctRegex!(`(?m)^#+\s*`);
    foreach (m; matchAll(text, numListRe))
        text = text.replace(m.hit, "");

    // Collapse multiple blank lines
    enum blankRe = ctRegex!(`\n{3,}`);
    foreach (m; matchAll(text, blankRe))
        text = text.replace(m.hit, "\n\n");

    return text.strip;
}

string stripNested(string text, string open, string close)
{
    string result;
    int depth = 0;
    size_t i = 0;

    while (i < text.length)
    {
        if (i + open.length <= text.length && text[i .. i + open.length] == open)
        {
            depth++;
            i += open.length;
        }
        else if (i + close.length <= text.length && text[i .. i + close.length] == close)
        {
            if (depth > 0)
                depth--;
            i += close.length;
        }
        else
        {
            if (depth == 0)
                result ~= text[i];
            i++;
        }
    }

    return result;
}