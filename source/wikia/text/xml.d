module wikia.text.xml;

import std.string : indexOf;

import wikia.text.ast;
import wikia.text.utils : stripTags, decodeEntities;

/// Parse PubMed/PMC XML article content into a Document AST.
/// Handles the JATS/NLM XML format used by NCBI.
Document parseXml(string src)
{
    XmlParser parser = XmlParser(src);
    parser.parse();
    return Document(parser.nodes, src);
}

private struct XmlParser
{
    string src;
    size_t pos;
    Node[] nodes;

    this(string src)
    {
        this.src = src;
        this.pos = 0;
        nodes.reserve(256);
    }

    void parse()
    {
        nodes ~= Node(NodeType.Document);
        uint childStart = cast(uint) nodes.length;

        while (pos < src.length)
        {
            skipWhitespace();
            if (pos >= src.length)
                break;

            if (matchAt("<!--"))
            {
                parseComment();
                continue;
            }

            if (src[pos] == '<')
            {
                if (dispatchTag())
                    continue;

                // Closing tag or processing instruction — skip.
                if (pos + 1 < src.length
                    && (src[pos + 1] == '/' || src[pos + 1] == '?'))
                {
                    skipToAfter('>');
                    continue;
                }

                skipTag();
                continue;
            }

            parseTextContent();
        }

        nodes[0].childStart = childStart;
        nodes[0].childEnd = cast(uint) nodes.length;
    }

    /// Dispatch on the current XML tag name.
    bool dispatchTag()
    {
        // Structural elements
        if (matchTag("article-title")) { parseSimpleElement("article-title", NodeType.Section, 1); return true; }
        if (matchTag("title"))         { parseSimpleElement("title", NodeType.Section, 2); return true; }
        if (matchTag("abstract"))      { parseSectionElement("abstract", "Abstract", 2); return true; }
        if (matchTag("body"))          { parseBodyElement(); return true; }
        if (matchTag("sec"))           { parseSec(); return true; }
        if (matchTag("p"))             { parseParagraphElement(); return true; }
        if (matchTag("list"))          { parseListElement(); return true; }

        // Skipped elements
        if (matchTag("table-wrap") || matchTag("table")) { skipElement(); return true; }
        if (matchTag("fig"))        { skipElement(); return true; }
        if (matchTag("ref-list"))   { skipElement(); return true; }

        // Inline elements
        if (matchTag("xref"))     { parseXref(); return true; }
        if (matchTag("ext-link")) { parseExtLink(); return true; }
        if (matchTag("bold") || matchTag("b"))
        {
            parseInlineElement("bold", NodeType.Styled, NodeFlags.Bold);
            return true;
        }
        if (matchTag("italic") || matchTag("i"))
        {
            parseInlineElement("italic", NodeType.Styled, NodeFlags.Italic);
            return true;
        }
        if (matchTag("sup") || matchTag("sub") || matchTag("sc") || matchTag("monospace"))
        {
            parseGenericInline();
            return true;
        }

        return false;
    }

    // --- Structural elements ---

    void parseSec()
    {
        skipToAfter('>');
        Node secNode = Node(NodeType.Section);
        secNode.level = 2;
        uint secIdx = cast(uint) nodes.length;
        nodes ~= secNode;
        uint childStart = cast(uint) nodes.length;

        while (pos < src.length)
        {
            skipWhitespace();
            if (pos >= src.length) break;

            if (matchClosing("sec"))     { skipToAfter('>'); break; }
            if (matchTag("title"))       { nodes[secIdx].text = extractElementText("title"); continue; }
            if (matchTag("sec"))         { parseSec(); continue; }
            if (matchTag("p"))           { parseParagraphElement(); continue; }
            if (matchTag("list"))        { parseListElement(); continue; }

            if (matchTag("table-wrap") || matchTag("table")
                || matchTag("fig") || matchTag("ref-list"))
            {
                skipElement();
                continue;
            }

            if (src[pos] == '<') { skipTag(); continue; }
            parseTextContent();
        }

        nodes[secIdx].childStart = childStart;
        nodes[secIdx].childEnd = cast(uint) nodes.length;
    }

    void parseBodyElement()
    {
        skipToAfter('>');
        while (pos < src.length)
        {
            skipWhitespace();
            if (pos >= src.length) break;
            if (matchClosing("body")) { skipToAfter('>'); break; }
            if (matchTag("sec"))      { parseSec(); continue; }
            if (matchTag("p"))        { parseParagraphElement(); continue; }
            if (src[pos] == '<')      { skipTag(); continue; }
            parseTextContent();
        }
    }

    void parseSectionElement(string tag, string heading, ubyte level)
    {
        skipToAfter('>');

        Node secNode = Node(NodeType.Section);
        secNode.text = heading;
        secNode.level = level;
        uint secIdx = cast(uint) nodes.length;
        nodes ~= secNode;
        uint childStart = cast(uint) nodes.length;

        while (pos < src.length)
        {
            skipWhitespace();
            if (pos >= src.length) break;
            if (matchClosing(tag)) { skipToAfter('>'); break; }
            if (matchTag("sec"))   { parseSec(); continue; }
            if (matchTag("p"))     { parseParagraphElement(); continue; }
            if (matchTag("title"))
            {
                parseSimpleElement("title", NodeType.Section, cast(ubyte)(level + 1));
                continue;
            }
            if (src[pos] == '<') { skipTag(); continue; }
            parseTextContent();
        }

        nodes[secIdx].childStart = childStart;
        nodes[secIdx].childEnd = cast(uint) nodes.length;
    }

    void parseParagraphElement()
    {
        skipToAfter('>');

        uint paragraphIdx = cast(uint) nodes.length;
        nodes ~= Node(NodeType.Paragraph);
        uint childStart = cast(uint) nodes.length;

        while (pos < src.length)
        {
            if (matchClosing("p")) { skipToAfter('>'); break; }

            if (pos < src.length && src[pos] == '<')
            {
                if (matchTag("bold") || matchTag("b"))
                    { parseInlineElement("bold", NodeType.Styled, NodeFlags.Bold); continue; }
                if (matchTag("italic") || matchTag("i"))
                    { parseInlineElement("italic", NodeType.Styled, NodeFlags.Italic); continue; }
                if (matchTag("xref"))     { parseXref(); continue; }
                if (matchTag("ext-link")) { parseExtLink(); continue; }
                skipTag();
                continue;
            }

            parseTextContent();
        }

        nodes[paragraphIdx].childStart = childStart;
        nodes[paragraphIdx].childEnd = cast(uint) nodes.length;
    }

    void parseListElement()
    {
        size_t tagStart = pos;
        skipToAfter('>');
        string tagText = src[tagStart..pos];

        bool ordered = tagText.indexOf("list-type=\"order\"") >= 0;
        NodeType listType = ordered ? NodeType.OrderedList : NodeType.UnorderedList;
        uint listIdx = cast(uint) nodes.length;
        nodes ~= Node(listType);
        uint childStart = cast(uint) nodes.length;

        while (pos < src.length)
        {
            skipWhitespace();
            if (pos >= src.length) break;
            if (matchClosing("list"))    { skipToAfter('>'); break; }
            if (matchTag("list-item"))   { parseListItem(); continue; }
            if (src[pos] == '<')         { skipTag(); continue; }
            parseTextContent();
        }

        nodes[listIdx].childStart = childStart;
        nodes[listIdx].childEnd = cast(uint) nodes.length;
    }

    void parseListItem()
    {
        skipToAfter('>');

        Node itemNode = Node(NodeType.ListItem);
        itemNode.level = 1;
        uint itemIdx = cast(uint) nodes.length;
        nodes ~= itemNode;
        uint childStart = cast(uint) nodes.length;

        while (pos < src.length)
        {
            skipWhitespace();
            if (matchClosing("list-item")) { skipToAfter('>'); break; }
            if (matchTag("p"))             { parseParagraphElement(); continue; }
            if (src[pos] == '<')           { skipTag(); continue; }
            parseTextContent();
        }

        nodes[itemIdx].childStart = childStart;
        nodes[itemIdx].childEnd = cast(uint) nodes.length;
    }

    // --- Inline elements ---

    void parseInlineElement(string tag, NodeType nodeType, NodeFlags flags = NodeFlags.None)
    {
        // Detect actual tag name from source for closing match.
        size_t start = pos + 1;
        skipToAfter('>');

        string closeTag = tag;
        if (tag == "bold" && start < src.length && src[start] == 'b'
            && (start + 1 >= src.length || src[start + 1] == '>' || src[start + 1] == ' '))
            closeTag = "b";
        if (tag == "italic" && start < src.length && src[start] == 'i'
            && (start + 1 >= src.length || src[start + 1] == '>' || src[start + 1] == ' '))
            closeTag = "i";

        uint styledIdx = cast(uint) nodes.length;
        Node styledNode = Node(nodeType);
        styledNode.flags = flags;
        nodes ~= styledNode;
        uint childStart = cast(uint) nodes.length;

        while (pos < src.length)
        {
            if (matchClosing(closeTag) || matchClosing(tag))
            {
                skipToAfter('>');
                break;
            }
            if (src[pos] == '<') { skipTag(); continue; }
            parseTextContent();
        }

        nodes[styledIdx].childStart = childStart;
        nodes[styledIdx].childEnd = cast(uint) nodes.length;
    }

    void parseGenericInline()
    {
        // Extract tag name.
        size_t start = pos + 1;
        size_t nameEnd = start;
        while (nameEnd < src.length && src[nameEnd] != ' '
            && src[nameEnd] != '>' && src[nameEnd] != '/')
            nameEnd++;
        string tagName = src[start..nameEnd];
        skipToAfter('>');

        size_t textStart = pos;
        string closeStr = "</"~tagName~">";
        ptrdiff_t closeIdx = src[pos..$].indexOf(closeStr);
        if (closeIdx >= 0)
        {
            size_t absClose = pos + closeIdx;
            if (absClose > textStart)
            {
                Node textNode = Node(NodeType.Text);
                textNode.text = src[textStart..absClose];
                nodes ~= textNode;
            }
            pos = absClose + closeStr.length;
        }
    }

    void parseXref()
    {
        skipToAfter('>');

        Node refNode = Node(NodeType.Reference);
        size_t textStart = pos;
        ptrdiff_t closeIdx = src[pos..$].indexOf("</xref>");
        if (closeIdx >= 0)
        {
            size_t absClose = pos + closeIdx;
            refNode.text = src[textStart..absClose];
            pos = absClose + 7;
        }
        nodes ~= refNode;
    }

    void parseExtLink()
    {
        size_t tagEnd = pos;
        ptrdiff_t rel = src[pos..$].indexOf('>');
        if (rel < 0)
        {
            pos = src.length;
            return;
        }
        tagEnd = pos + rel;

        string tagAttrs = src[pos..tagEnd];
        string href = extractAttr(tagAttrs, "xlink:href");
        if (href.length == 0)
            href = extractAttr(tagAttrs, "href");
        pos = tagEnd + 1;

        Node extLinkNode = Node(NodeType.ExtLink);
        extLinkNode.target = href;

        size_t textStart = pos;
        ptrdiff_t closeIdx = src[pos..$].indexOf("</ext-link>");
        if (closeIdx >= 0)
        {
            size_t absClose = pos + closeIdx;
            extLinkNode.text = src[textStart..absClose];
            pos = absClose + 11;
        }
        nodes ~= extLinkNode;
    }

    void parseSimpleElement(string tag, NodeType nodeType, ubyte level)
    {
        string text = extractElementText(tag);
        Node elementNode = Node(nodeType);
        elementNode.text = text;
        elementNode.level = level;
        nodes ~= elementNode;
    }

    // --- Text content ---

    void parseTextContent()
    {
        size_t start = pos;
        while (pos < src.length && src[pos] != '<')
            pos++;

        if (pos > start)
        {
            string text = decodeEntities(src[start..pos]);
            if (text.length > 0)
            {
                Node textNode = Node(NodeType.Text);
                textNode.text = text;
                nodes ~= textNode;
            }
        }
    }

    void parseComment()
    {
        pos += 4;
        ptrdiff_t endIdx = src[pos..$].indexOf("-->");
        if (endIdx < 0)
        {
            nodes ~= Node(NodeType.Comment, src[pos..$]);
            pos = src.length;
        }
        else
        {
            size_t absEnd = pos + endIdx;
            nodes ~= Node(NodeType.Comment, src[pos..absEnd]);
            pos = absEnd + 3;
        }
    }

    // --- Utility ---

    void skipWhitespace()
    {
        while (pos < src.length && (src[pos] == ' ' || src[pos] == '\n'
            || src[pos] == '\r' || src[pos] == '\t'))
            pos++;
    }

    void skipToAfter(char ch)
    {
        while (pos < src.length && src[pos] != ch)
            pos++;
        if (pos < src.length)
            pos++;
    }

    void skipTag()
    {
        skipToAfter('>');
    }

    void skipElement()
    {
        if (pos >= src.length || src[pos] != '<')
            return;
        size_t start = pos + 1;
        size_t nameEnd = start;
        while (nameEnd < src.length && src[nameEnd] != ' '
            && src[nameEnd] != '>' && src[nameEnd] != '/')
            nameEnd++;

        string tagName = src[start..nameEnd];
        skipToAfter('>');

        // Self-closing check.
        if (nameEnd > 0 && pos > 1 && src[pos - 2] == '/')
            return;

        // Find matching close, handling nesting.
        int depth = 1;
        string openStr = "<"~tagName;
        string closeStr = "</"~tagName~">";
        while (pos < src.length && depth > 0)
        {
            if (matchAt(closeStr))
            {
                depth--;
                pos += closeStr.length;
            }
            else if (matchAt(openStr))
            {
                depth++;
                skipToAfter('>');
            }
            else
                pos++;
        }
    }

    bool matchTag(string name) const pure nothrow @nogc
    {
        if (pos + 1 + name.length > src.length) return false;
        if (src[pos] != '<') return false;
        if (src[pos + 1..pos + 1 + name.length] != name) return false;
        size_t after = pos + 1 + name.length;
        if (after >= src.length) return false;
        return src[after] == '>' || src[after] == ' '
            || src[after] == '/' || src[after] == '\n';
    }

    bool matchClosing(string name) const pure nothrow @nogc
    {
        if (pos + 2 + name.length > src.length) return false;
        if (src[pos] != '<' || src[pos + 1] != '/') return false;
        if (src[pos + 2..pos + 2 + name.length] != name) return false;
        size_t after = pos + 2 + name.length;
        return after < src.length && (src[after] == '>' || src[after] == ' ');
    }

    bool matchAt(string str) const pure nothrow @nogc
    {
        return pos + str.length <= src.length && src[pos..pos + str.length] == str;
    }

    string extractElementText(string tag)
    {
        skipToAfter('>');
        size_t textStart = pos;
        string closeTag = "</"~tag~">";
        ptrdiff_t closeIdx = src[pos..$].indexOf(closeTag);
        if (closeIdx < 0)
            return null;
        size_t absClose = pos + closeIdx;
        string raw = src[textStart..absClose];
        pos = absClose + closeTag.length;
        return stripTags(raw);
    }

    static string extractAttr(string tag, string attr)
    {
        string search = attr~"=\"";
        ptrdiff_t idx = tag.indexOf(search);
        if (idx < 0) return null;
        size_t valStart = idx + search.length;
        size_t valEnd = valStart;
        while (valEnd < tag.length && tag[valEnd] != '"')
            valEnd++;
        return tag[valStart..valEnd];
    }
}
