module wikia.text.xml;

import wikia.text.ast;

/// Parse PubMed/PMC XML article content into a Document AST.
/// This handles the JATS/NLM XML format used by NCBI.
Document parseXml(string src)
{
    auto parser = XmlParser(src);
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
        // Root document node.
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
                if (src[pos + 1] == '/' || src[pos + 1] == '?')
                {
                    skipToAfter('>');
                    continue;
                }

                // Unknown opening tag.
                skipTag();
                continue;
            }

            parseTextContent();
        }

        nodes[0].childStart = childStart;
        nodes[0].childEnd = cast(uint) nodes.length;
    }

    /// Dispatch on the current XML tag name. Returns true if a known
    /// tag was matched and handled, false otherwise.
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
        if (matchTag("bold") || matchTag("b"))   { parseInlineElement("bold", NodeType.Bold); return true; }
        if (matchTag("italic") || matchTag("i")) { parseInlineElement("italic", NodeType.Italic); return true; }
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
        skipToAfter('>'); // skip <sec ...>
        Node secNode = Node(NodeType.Section);
        secNode.level = 2;
        uint secIdx = cast(uint) nodes.length;
        nodes ~= secNode;
        uint childStart = cast(uint) nodes.length;

        while (pos < src.length)
        {
            skipWhitespace();
            if (pos >= src.length) break;

            if (matchClosing("sec"))
            {
                skipToAfter('>');
                break;
            }

            if (matchTag("title"))
            {
                const(char)[] titleText = extractElementText("title");
                nodes[secIdx].text = titleText;
                continue;
            }

            if (matchTag("sec"))
            {
                parseSec();
                continue;
            }

            if (matchTag("p"))
            {
                parseParagraphElement();
                continue;
            }

            if (matchTag("list"))
            {
                parseListElement();
                continue;
            }

            if (matchTag("table-wrap") || matchTag("table") ||
                matchTag("fig") || matchTag("ref-list"))
            {
                skipElement();
                continue;
            }

            if (src[pos] == '<')
            {
                skipTag();
                continue;
            }

            parseTextContent();
        }

        nodes[secIdx].childStart = childStart;
        nodes[secIdx].childEnd = cast(uint) nodes.length;
    }

    void parseBodyElement()
    {
        skipToAfter('>'); // skip <body ...>

        while (pos < src.length)
        {
            skipWhitespace();
            if (pos >= src.length) break;

            if (matchClosing("body"))
            {
                skipToAfter('>');
                break;
            }

            if (matchTag("sec"))
            {
                parseSec();
                continue;
            }

            if (matchTag("p"))
            {
                parseParagraphElement();
                continue;
            }

            if (src[pos] == '<')
            {
                skipTag();
                continue;
            }

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

            if (matchClosing(tag))
            {
                skipToAfter('>');
                break;
            }

            if (matchTag("sec"))
            {
                parseSec();
                continue;
            }

            if (matchTag("p"))
            {
                parseParagraphElement();
                continue;
            }

            if (matchTag("title"))
            {
                // Sub-title inside abstract.
                parseSimpleElement("title", NodeType.Section, cast(ubyte)(level + 1));
                continue;
            }

            if (src[pos] == '<')
            {
                skipTag();
                continue;
            }

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
            if (matchClosing("p"))
            {
                skipToAfter('>');
                break;
            }

            if (pos < src.length && src[pos] == '<')
            {
                if (matchTag("bold") || matchTag("b"))
                {
                    parseInlineElement("bold", NodeType.Bold);
                    continue;
                }
                if (matchTag("italic") || matchTag("i"))
                {
                    parseInlineElement("italic", NodeType.Italic);
                    continue;
                }
                if (matchTag("xref"))
                {
                    parseXref();
                    continue;
                }
                if (matchTag("ext-link"))
                {
                    parseExtLink();
                    continue;
                }
                // Skip unknown inline tags.
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
        // Determine list type from attributes.
        size_t tagStart = pos;
        skipToAfter('>');
        const(char)[] tagText = src[tagStart..pos];

        bool ordered = sliceContains(tagText, "list-type=\"order\"");
        NodeType listType = ordered ? NodeType.OrderedList : NodeType.UnorderedList;
        uint listIdx = cast(uint) nodes.length;
        nodes ~= Node(listType);
        uint childStart = cast(uint) nodes.length;

        while (pos < src.length)
        {
            skipWhitespace();
            if (pos >= src.length) break;

            if (matchClosing("list"))
            {
                skipToAfter('>');
                break;
            }

            if (matchTag("list-item"))
            {
                parseListItem();
                continue;
            }

            if (src[pos] == '<')
            {
                skipTag();
                continue;
            }

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
            if (matchClosing("list-item"))
            {
                skipToAfter('>');
                break;
            }

            if (matchTag("p"))
            {
                parseParagraphElement();
                continue;
            }

            if (src[pos] == '<')
            {
                skipTag();
                continue;
            }

            parseTextContent();
        }

        nodes[itemIdx].childStart = childStart;
        nodes[itemIdx].childEnd = cast(uint) nodes.length;
    }

    // --- Inline elements ---

    void parseInlineElement(string tag, NodeType nodeType)
    {
        // Determine actual tag name from source for closing match.
        size_t start = pos + 1; // after '<'
        skipToAfter('>');

        // Find the actual tag name.
        string closeTag = tag;
        if (tag == "bold" && start < src.length && src[start] == 'b'
            && (start + 1 >= src.length || src[start + 1] == '>'
                || src[start + 1] == ' '))
            closeTag = "b";
        if (tag == "italic" && start < src.length && src[start] == 'i'
            && (start + 1 >= src.length || src[start + 1] == '>'
                || src[start + 1] == ' '))
            closeTag = "i";

        uint fmtIdx = cast(uint) nodes.length;
        nodes ~= Node(nodeType);
        uint childStart = cast(uint) nodes.length;

        while (pos < src.length)
        {
            if (matchClosing(closeTag) || matchClosing(tag))
            {
                skipToAfter('>');
                break;
            }

            if (src[pos] == '<')
            {
                skipTag();
                continue;
            }

            parseTextContent();
        }

        nodes[fmtIdx].childStart = childStart;
        nodes[fmtIdx].childEnd = cast(uint) nodes.length;
    }

    void parseGenericInline()
    {
        // Extract tag name.
        size_t start = pos + 1;
        size_t nameEnd = start;
        while (nameEnd < src.length && src[nameEnd] != ' '
            && src[nameEnd] != '>' && src[nameEnd] != '/')
            nameEnd++;
        string tagName = cast(string) src[start .. nameEnd];
        skipToAfter('>');

        // Just extract text until close.
        size_t textStart = pos;
        string closeStr = "</" ~ tagName ~ ">";
        size_t closeIdx = indexOfStr(pos, closeStr);
        if (closeIdx != size_t.max)
        {
            if (closeIdx > textStart)
            {
                Node textNode = Node(NodeType.Text);
                textNode.text = src[textStart .. closeIdx];
                nodes ~= textNode;
            }
            pos = closeIdx + closeStr.length;
        }
    }

    void parseXref()
    {
        // <xref ref-type="bibr" rid="ref1">1</xref>
        size_t tagStart = pos;
        skipToAfter('>');

        Node refNode = Node(NodeType.Reference);
        size_t textStart = pos;
        size_t closeIdx = indexOfStr(pos, "</xref>");
        if (closeIdx != size_t.max)
        {
            refNode.text = src[textStart .. closeIdx];
            pos = closeIdx + 7;
        }
        nodes ~= refNode;
    }

    void parseExtLink()
    {
        // <ext-link ext-link-type="uri" xlink:href="...">text</ext-link>
        size_t tagStart = pos;
        size_t tagEnd = indexOfChar(pos, '>');
        if (tagEnd == size_t.max)
        {
            pos = src.length;
            return;
        }

        const(char)[] tagAttrs = src[pos .. tagEnd];
        const(char)[] href = extractAttr(tagAttrs, "xlink:href");
        if (href.length == 0)
            href = extractAttr(tagAttrs, "href");
        pos = tagEnd + 1;

        Node extLinkNode = Node(NodeType.ExtLink);
        extLinkNode.target = href;

        size_t textStart = pos;
        size_t closeIdx = indexOfStr(pos, "</ext-link>");
        if (closeIdx != size_t.max)
        {
            extLinkNode.text = src[textStart .. closeIdx];
            pos = closeIdx + 11;
        }
        nodes ~= extLinkNode;
    }

    void parseSimpleElement(string tag, NodeType nodeType, ubyte level)
    {
        const(char)[] text = extractElementText(tag);
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
            const(char)[] text = decodeEntities(src[start .. pos]);
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
        pos += 4; // skip "<!--"
        size_t endIdx = indexOfStr(pos, "-->");
        if (endIdx == size_t.max)
        {
            nodes ~= Node(NodeType.Comment, src[pos..$]);
            pos = src.length;
        }
        else
        {
            nodes ~= Node(NodeType.Comment, src[pos..endIdx]);
            pos = endIdx + 3;
        }
    }

    // --- Utility ---

    void skipWhitespace()
    {
        while (pos < src.length && (src[pos] == ' ' || src[pos] == '\n'
            || src[pos] == '\r' || src[pos] == '\t'))
            pos++;
    }

    void skipToAfter(char c)
    {
        while (pos < src.length && src[pos] != c)
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
        // Extract tag name.
        if (pos >= src.length || src[pos] != '<') return;
        size_t start = pos + 1;
        size_t nameEnd = start;
        while (nameEnd < src.length && src[nameEnd] != ' '
            && src[nameEnd] != '>' && src[nameEnd] != '/')
            nameEnd++;

        string tagName = cast(string) src[start..nameEnd];
        skipToAfter('>');

        // Check if it was self-closing.
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

    bool matchTag(string name) const
    {
        if (pos + 1 + name.length > src.length) return false;
        if (src[pos] != '<') return false;
        if (src[pos + 1..pos + 1 + name.length] != name) return false;
        size_t after = pos + 1 + name.length;
        if (after >= src.length) return false;
        return src[after] == '>' || src[after] == ' ' || src[after] == '/' || src[after] == '\n';
    }

    bool matchClosing(string name) const
    {
        if (pos + 2 + name.length > src.length) return false;
        if (src[pos] != '<' || src[pos + 1] != '/') return false;
        if (src[pos + 2..pos + 2 + name.length] != name) return false;
        size_t after = pos + 2 + name.length;
        return after < src.length && (src[after] == '>' || src[after] == ' ');
    }

    bool matchAt(string s) const
    {
        return pos + s.length <= src.length && src[pos..pos + s.length] == s;
    }

    const(char)[] extractElementText(string tag)
    {
        skipToAfter('>');
        size_t textStart = pos;
        string closeTag = "</"~tag~">";
        size_t closeIdx = indexOfStr(pos, closeTag);
        if (closeIdx == size_t.max)
            return null;
        const(char)[] raw = src[textStart..closeIdx];
        pos = closeIdx + closeTag.length;
        return stripTags(raw);
    }

    size_t indexOfChar(size_t from, char c) const
    {
        for (size_t j = from; j < src.length; j++)
            if (src[j] == c) return j;
        return size_t.max;
    }

    size_t indexOfStr(size_t from, string s) const
    {
        if (s.length == 0) return from;
        if (from + s.length > src.length) return size_t.max;
        for (size_t j = from; j + s.length <= src.length; j++)
            if (src[j..j + s.length] == s) return j;
        return size_t.max;
    }

    // --- Static helpers ---

    static const(char)[] stripTags(const(char)[] text)
    {
        // Remove all XML tags, leaving only text content.
        const(char)[] result;
        size_t i = 0;
        size_t start = 0;
        while (i < text.length)
        {
            if (text[i] == '<')
            {
                if (i > start)
                    result ~= text[start..i];
                while (i < text.length && text[i] != '>')
                    i++;
                if (i < text.length) i++; // skip '>'
                start = i;
            }
            else
                i++;
        }
        if (start < text.length)
            result ~= text[start..$];
        return result;
    }

    static const(char)[] extractAttr(const(char)[] tag, const(char)[] attr)
    {
        // Find attr="value" in tag text.
        string search = cast(string)(attr~"=\"");
        size_t idx = sliceIndexOf(tag, search);
        if (idx == size_t.max) return null;
        size_t valStart = idx + search.length;
        size_t valEnd = valStart;
        while (valEnd < tag.length && tag[valEnd] != '"')
            valEnd++;
        return tag[valStart..valEnd];
    }

    static size_t sliceIndexOf(const(char)[] hay, const(char)[] needle)
    {
        if (needle.length == 0) return 0;
        if (hay.length < needle.length) return size_t.max;
        for (size_t j = 0; j + needle.length <= hay.length; j++)
            if (hay[j..j + needle.length] == needle) return j;
        return size_t.max;
    }

    static bool sliceContains(const(char)[] hay, const(char)[] needle)
    {
        return sliceIndexOf(hay, needle) != size_t.max;
    }

    static const(char)[] decodeEntities(const(char)[] text)
    {
        // Quick check: if no '&', return as-is.
        bool hasAmp = false;
        foreach (c; text)
        {
            if (c == '&') { hasAmp = true; break; }
        }
        if (!hasAmp) return text;

        const(char)[] result;
        size_t i = 0;
        size_t start = 0;
        while (i < text.length)
        {
            if (text[i] == '&')
            {
                if (i > start)
                    result ~= text[start..i];

                size_t semicol = i + 1;
                while (semicol < text.length && semicol < i + 12 && text[semicol] != ';')
                    semicol++;

                if (semicol < text.length && text[semicol] == ';')
                {
                    const(char)[] entity = text[i + 1..semicol];
                    if (entity == "amp") result ~= "&";
                    else if (entity == "lt") result ~= "<";
                    else if (entity == "gt") result ~= ">";
                    else if (entity == "quot") result ~= "\"";
                    else if (entity == "apos") result ~= "'";
                    else if (entity == "nbsp") result ~= " ";
                    else if (entity == "ndash") result ~= "\u2013";
                    else if (entity == "mdash") result ~= "\u2014";
                    else if (entity.length > 1 && entity[0] == '#')
                    {
                        // Numeric entity — just output the raw text.
                        result ~= text[i..semicol + 1];
                    }
                    else
                        result ~= text[i..semicol + 1];

                    i = semicol + 1;
                    start = i;
                }
                else
                {
                    result ~= "&";
                    i++;
                    start = i;
                }
            }
            else
                i++;
        }
        if (start < text.length)
            result ~= text[start..$];
        return result;
    }
}
