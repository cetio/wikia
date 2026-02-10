module wikia.text.wikitext;

import wikia.text.ast;
import std.string : indexOf, strip, stripRight;

/// Parse wikitext source into a Document AST.
/// Zero-copy where possible: text nodes hold slices into `src`.
Document parseWikitext(string src)
{
    auto parser = WikitextParser(src);
    parser.parse();
    return Document(parser.nodes, src);
}

private struct WikitextParser
{
    string src;
    size_t pos;
    Node[] nodes;

    // Builder stack: tracks parent node indices for nesting.
    uint[] parentStack;

    this(string src)
    {
        this.src = src;
        this.pos = 0;
        // Pre-allocate for typical documents.
        nodes.reserve(512);
        parentStack.reserve(16);
    }

    void parse()
    {
        // Root document node (index 0).
        nodes ~= Node(NodeType.Document);
        parentStack ~= 0;

        parseBody();

        // Finalize root children.
        nodes[0].childStart = 1;
        nodes[0].childEnd = cast(uint) nodes.length;

        // Fix up: the root's direct children are those at depth 1.
        // We need to restructure so sections own their content.
        restructure();
    }

    // --- Top-level block parsing ---

    void parseBody()
    {
        while (pos < src.length)
        {
            skipComments();
            if (pos >= src.length)
                break;

            // Heading
            if (atLineStart() && peek() == '=')
            {
                if (tryParseHeading())
                    continue;
            }

            // Redirect
            if (pos + 9 < src.length && src[pos .. pos + 9] == "#REDIRECT")
            {
                parseRedirect();
                continue;
            }

            // Horizontal rule
            if (atLineStart() && remaining() >= 4 && src[pos .. pos + 4] == "----")
            {
                size_t end = pos + 4;
                while (end < src.length && src[end] == '-')
                    end++;
                nodes ~= Node(NodeType.HorizontalRule);
                pos = end;
                skipNewlines();
                continue;
            }

            // Unordered list
            if (atLineStart() && peek() == '*')
            {
                parseList(NodeType.UnorderedList, '*');
                continue;
            }

            // Ordered list
            if (atLineStart() && peek() == '#')
            {
                parseList(NodeType.OrderedList, '#');
                continue;
            }

            // Definition list
            if (atLineStart() && (peek() == ';' || peek() == ':'))
            {
                parseDefinitionList();
                continue;
            }

            // Table
            if (atLineStart() && remaining() >= 2 && src[pos .. pos + 2] == "{|")
            {
                parseTable();
                continue;
            }

            // Preformatted (lines starting with space)
            if (atLineStart() && peek() == ' ')
            {
                parsePreformatted();
                continue;
            }

            // Nowiki block
            if (matchAt("<nowiki>") || matchAt("<nowiki/>") || matchAt("<nowiki />"))
            {
                parseNoWiki();
                continue;
            }

            // Math block
            if (matchAt("<math>") || matchAt("<math "))
            {
                parseMathBlock();
                continue;
            }

            // Blockquote
            if (matchAt("<blockquote>") || matchAt("<blockquote "))
            {
                parseHtmlBlock("blockquote", NodeType.BlockQuote);
                continue;
            }

            // Category
            if (matchAt("[[Category:") || matchAt("[[category:"))
            {
                parseCategory();
                continue;
            }

            // Block-level template {{ ... }} (handles multi-line templates
            // like {{Infobox ...}} that may contain blank lines).
            if (remaining() >= 2 && src[pos .. pos + 2] == "{{")
            {
                size_t closePos = findMatchingClose(src, pos + 2, "{{", "}}");
                if (closePos != size_t.max)
                {
                    auto tpl = Node(NodeType.Template);
                    tpl.text = src[pos + 2 .. closePos];
                    nodes ~= tpl;
                    pos = closePos + 2;
                    skipNewlines();
                    continue;
                }
            }

            // Block-level <ref>...</ref> that starts a line.
            if (matchAt("<ref"))
            {
                if (tryParseBlockRef())
                    continue;
            }

            // Otherwise: paragraph of inline content
            parseParagraph();
        }
    }

    // --- Headings ---

    bool tryParseHeading()
    {
        size_t start = pos;
        int level = 0;
        while (pos + level < src.length && src[pos + level] == '=' && level < 6)
            level++;

        if (level < 2)
            return false;

        size_t hStart = pos + level;
        // Find the closing === on the same line.
        size_t lineEnd = findLineEnd(hStart);
        // Scan backwards from lineEnd for closing '='.
        size_t closeEnd = lineEnd;
        while (closeEnd > hStart && src[closeEnd - 1] == ' ')
            closeEnd--;
        size_t closeStart = closeEnd;
        while (closeStart > hStart && src[closeStart - 1] == '=')
            closeStart--;

        int closeLevel = cast(int)(closeEnd - closeStart);
        if (closeLevel < 2)
        {
            // Not a valid heading, treat as paragraph.
            pos = start;
            return false;
        }

        int effectiveLevel = level < closeLevel ? level : closeLevel;

        const(char)[] headingText = src[hStart .. closeStart].strip;

        auto secNode = Node(NodeType.Section);
        secNode.level = cast(ubyte) effectiveLevel;
        secNode.text = headingText;
        nodes ~= secNode;

        pos = lineEnd;
        skipNewlines();
        return true;
    }

    // --- Lists ---

    void parseList(NodeType listType, char marker)
    {
        auto listNode = Node(listType);
        uint listIdx = cast(uint) nodes.length;
        nodes ~= listNode;

        uint firstChild = cast(uint) nodes.length;

        while (pos < src.length && atLineStart() && peek() == marker)
        {
            int depth = 0;
            while (pos + depth < src.length && src[pos + depth] == marker)
                depth++;
            pos += depth;

            size_t lineEnd = findLineEnd(pos);
            const(char)[] content = src[pos .. lineEnd].strip;
            pos = lineEnd;
            skipNewlines();

            auto item = Node(NodeType.ListItem);
            item.level = cast(ubyte) depth;

            // Parse inline content of the list item.
            uint itemIdx = cast(uint) nodes.length;
            nodes ~= item;
            uint inlineStart = cast(uint) nodes.length;
            parseInlineInto(content);
            nodes[itemIdx].childStart = inlineStart;
            nodes[itemIdx].childEnd = cast(uint) nodes.length;
        }

        nodes[listIdx].childStart = firstChild;
        nodes[listIdx].childEnd = cast(uint) nodes.length;
    }

    // --- Definition list ---

    void parseDefinitionList()
    {
        auto dlNode = Node(NodeType.DefinitionList);
        uint dlIdx = cast(uint) nodes.length;
        nodes ~= dlNode;
        uint firstChild = cast(uint) nodes.length;

        while (pos < src.length && atLineStart() && (peek() == ';' || peek() == ':'))
        {
            char c = src[pos];
            pos++;
            size_t lineEnd = findLineEnd(pos);
            const(char)[] content = src[pos .. lineEnd].strip;
            pos = lineEnd;
            skipNewlines();

            NodeType nt = c == ';' ? NodeType.DefinitionTerm : NodeType.DefinitionDesc;
            auto item = Node(nt);
            uint itemIdx = cast(uint) nodes.length;
            nodes ~= item;
            uint inlineStart = cast(uint) nodes.length;
            parseInlineInto(content);
            nodes[itemIdx].childStart = inlineStart;
            nodes[itemIdx].childEnd = cast(uint) nodes.length;
        }

        nodes[dlIdx].childStart = firstChild;
        nodes[dlIdx].childEnd = cast(uint) nodes.length;
    }

    // --- Tables ---

    void parseTable()
    {
        pos += 2; // skip "{|"
        // Skip table attributes on the first line.
        size_t lineEnd = findLineEnd(pos);
        pos = lineEnd;
        skipNewlines();

        auto tableNode = Node(NodeType.Table);
        uint tableIdx = cast(uint) nodes.length;
        nodes ~= tableNode;
        uint firstChild = cast(uint) nodes.length;

        while (pos < src.length)
        {
            if (remaining() >= 2 && src[pos .. pos + 2] == "|}")
            {
                pos += 2;
                skipNewlines();
                break;
            }

            // Caption
            if (remaining() >= 2 && src[pos .. pos + 2] == "|+")
            {
                pos += 2;
                lineEnd = findLineEnd(pos);
                auto cap = Node(NodeType.TableCaption);
                cap.text = src[pos .. lineEnd].strip;
                nodes ~= cap;
                pos = lineEnd;
                skipNewlines();
                continue;
            }

            // Row separator
            if (remaining() >= 2 && src[pos .. pos + 2] == "|-")
            {
                pos += 2;
                lineEnd = findLineEnd(pos);
                pos = lineEnd;
                skipNewlines();

                parseTableRow();
                continue;
            }

            // Cells without explicit row start (first row).
            if (peek() == '!' || peek() == '|')
            {
                parseTableRow();
                continue;
            }

            // Skip unrecognized lines inside table.
            lineEnd = findLineEnd(pos);
            pos = lineEnd;
            skipNewlines();
        }

        nodes[tableIdx].childStart = firstChild;
        nodes[tableIdx].childEnd = cast(uint) nodes.length;
    }

    void parseTableRow()
    {
        auto rowNode = Node(NodeType.TableRow);
        uint rowIdx = cast(uint) nodes.length;
        nodes ~= rowNode;
        uint firstChild = cast(uint) nodes.length;

        while (pos < src.length)
        {
            // End of table or next row.
            if (remaining() >= 2 && (src[pos .. pos + 2] == "|}" || src[pos .. pos + 2] == "|-"))
                break;

            bool isHeader = (peek() == '!');
            if (peek() == '|' || peek() == '!')
            {
                pos++;
                parseTableCells(isHeader);
            }
            else
                break;
        }

        nodes[rowIdx].childStart = firstChild;
        nodes[rowIdx].childEnd = cast(uint) nodes.length;
    }

    void parseTableCells(bool isHeader)
    {
        size_t lineEnd = findLineEnd(pos);
        const(char)[] line = src[pos .. lineEnd];
        pos = lineEnd;
        skipNewlines();

        // Cells can be separated by || or !!
        const(char)[] sep = isHeader ? "!!" : "||";
        size_t cellStart = 0;

        while (cellStart < line.length)
        {
            size_t sepIdx = sliceIndexOf(line[cellStart .. $], sep);
            const(char)[] cellText;
            if (sepIdx == size_t.max)
            {
                cellText = line[cellStart .. $];
                cellStart = line.length;
            }
            else
            {
                cellText = line[cellStart .. cellStart + sepIdx];
                cellStart += sepIdx + sep.length;
            }

            // Strip attributes (text after last '|' if present, but not '||')
            auto pipeIdx = sliceIndexOf(cellText, "|");
            if (pipeIdx != size_t.max)
                cellText = cellText[pipeIdx + 1 .. $];

            NodeType ct = isHeader ? NodeType.TableHeader : NodeType.TableCell;
            auto cell = Node(ct);
            uint cellIdx = cast(uint) nodes.length;
            nodes ~= cell;
            uint inlineStart = cast(uint) nodes.length;
            parseInlineInto(cellText.strip);
            nodes[cellIdx].childStart = inlineStart;
            nodes[cellIdx].childEnd = cast(uint) nodes.length;
        }
    }

    // --- Preformatted ---

    void parsePreformatted()
    {
        // Collect all space-prefixed lines, stripping the leading space.
        const(char)[] content;
        while (pos < src.length && atLineStart() && peek() == ' ')
        {
            pos++; // skip leading space
            size_t lineEnd = findLineEnd(pos);
            if (content.length > 0)
                content = content ~ "\n" ~ src[pos .. lineEnd];
            else
                content = src[pos .. lineEnd];
            pos = lineEnd;
            if (pos < src.length && src[pos] == '\n')
                pos++;
        }

        if (content.length > 0)
        {
            auto pNode = Node(NodeType.Paragraph);
            uint pIdx = cast(uint) nodes.length;
            nodes ~= pNode;
            uint childStart = cast(uint) nodes.length;
            parseInlineInto(content);
            nodes[pIdx].childStart = childStart;
            nodes[pIdx].childEnd = cast(uint) nodes.length;
        }
    }

    // --- Special blocks ---

    void parseNoWiki()
    {
        // Handle self-closing <nowiki/> and <nowiki />
        if (matchAt("<nowiki/>"))
        {
            pos += 9;
            return;
        }
        if (matchAt("<nowiki />"))
        {
            pos += 10;
            return;
        }

        pos += 8; // skip "<nowiki>"
        size_t endIdx = indexOfStr(pos, "</nowiki>");
        if (endIdx == size_t.max)
        {
            nodes ~= Node(NodeType.NoWiki, src[pos .. $]);
            pos = src.length;
        }
        else
        {
            nodes ~= Node(NodeType.NoWiki, src[pos .. endIdx]);
            pos = endIdx + 9;
        }
    }

    void parseMathBlock()
    {
        size_t tagEnd = indexOfChar(pos, '>');
        if (tagEnd == size_t.max)
        {
            pos = src.length;
            return;
        }
        pos = tagEnd + 1;
        size_t endIdx = indexOfStr(pos, "</math>");
        if (endIdx == size_t.max)
        {
            nodes ~= Node(NodeType.Math, src[pos .. $]);
            pos = src.length;
        }
        else
        {
            nodes ~= Node(NodeType.Math, src[pos .. endIdx]);
            pos = endIdx + 7;
        }
    }

    void parseHtmlBlock(string tag, NodeType nt)
    {
        size_t tagEnd = indexOfChar(pos, '>');
        if (tagEnd == size_t.max)
        {
            pos = src.length;
            return;
        }
        pos = tagEnd + 1;
        string closeTag = "</" ~ tag ~ ">";
        size_t endIdx = indexOfStr(pos, closeTag);
        if (endIdx == size_t.max)
        {
            auto n = Node(nt);
            n.text = src[pos .. $];
            nodes ~= n;
            pos = src.length;
        }
        else
        {
            auto n = Node(nt);
            uint nIdx = cast(uint) nodes.length;
            nodes ~= n;
            uint childStart = cast(uint) nodes.length;
            parseInlineInto(src[pos .. endIdx]);
            nodes[nIdx].childStart = childStart;
            nodes[nIdx].childEnd = cast(uint) nodes.length;
            pos = endIdx + closeTag.length;
        }
    }

    void parseCategory()
    {
        pos += 2; // skip "[["
        size_t close = indexOfStr(pos, "]]");
        if (close == size_t.max)
        {
            pos = src.length;
            return;
        }
        // "Category:Name|Sortkey"
        const(char)[] inner = src[pos .. close];
        // Skip "Category:"
        size_t colon = sliceIndexOf(inner, ":");
        if (colon != size_t.max)
            inner = inner[colon + 1 .. $];
        auto pipeIdx = sliceIndexOf(inner, "|");
        const(char)[] name = pipeIdx != size_t.max ? inner[0 .. pipeIdx] : inner;

        auto cat = Node(NodeType.Category);
        cat.text = name.strip;
        nodes ~= cat;
        pos = close + 2;
        skipNewlines();
    }

    void parseRedirect()
    {
        pos += 9; // skip "#REDIRECT"
        while (pos < src.length && src[pos] == ' ')
            pos++;
        size_t close = indexOfStr(pos, "]]");
        if (close == size_t.max)
        {
            pos = src.length;
            return;
        }
        const(char)[] target = src[pos .. close];
        if (target.length >= 2 && target[0 .. 2] == "[[")
            target = target[2 .. $];
        auto rd = Node(NodeType.Redirect);
        rd.target = target.strip;
        nodes ~= rd;
        pos = close + 2;
    }

    // --- Block-level ref ---

    bool tryParseBlockRef()
    {
        // Handle <ref ... /> (self-closing) and <ref>...</ref> at block level.
        size_t tagEnd = indexOfChar(pos, '>');
        if (tagEnd == size_t.max)
            return false;

        // Self-closing?
        if (src[tagEnd - 1] == '/' || (tagEnd >= 2 && src[tagEnd - 1] == ' '
            && tagEnd >= pos + 1 && src[tagEnd - 2] == '/'))
        {
            auto refNode = Node(NodeType.Reference);
            refNode.text = src[pos .. tagEnd + 1];
            nodes ~= refNode;
            pos = tagEnd + 1;
            skipNewlines();
            return true;
        }

        // Non-self-closing: find </ref>
        size_t endRef = indexOfStr(tagEnd + 1, "</ref>");
        if (endRef != size_t.max)
        {
            auto refNode = Node(NodeType.Reference);
            refNode.text = src[tagEnd + 1 .. endRef];
            nodes ~= refNode;
            pos = endRef + 6;
            skipNewlines();
            return true;
        }

        return false;
    }

    // --- Paragraphs ---

    void parseParagraph()
    {
        // Collect inline content until we hit a blank line or block element.
        // Track <ref> nesting to avoid breaking inside multi-line refs.
        size_t start = pos;
        int refDepth = 0;

        while (pos < src.length)
        {
            // Track <ref> open/close to avoid splitting refs.
            if (pos + 5 < src.length && src[pos .. pos + 4] == "<ref"
                && (src[pos + 4] == '>' || src[pos + 4] == ' '))
            {
                refDepth++;
            }
            if (pos + 6 <= src.length && src[pos .. pos + 6] == "</ref>")
            {
                if (refDepth > 0) refDepth--;
                pos += 6;
                continue;
            }
            // Self-closing <ref ... />
            if (refDepth > 0 && src[pos] == '/' && pos + 1 < src.length
                && src[pos + 1] == '>')
            {
                refDepth--;
                pos += 2;
                continue;
            }

            // Only check paragraph breaks when not inside a <ref>.
            if (refDepth <= 0)
            {
                // Blank line ends paragraph.
                if (pos + 1 < src.length && src[pos] == '\n'
                    && src[pos + 1] == '\n')
                    break;
                // Check for block-level starts on next line.
                if (src[pos] == '\n' && pos + 1 < src.length)
                {
                    char next = src[pos + 1];
                    if (next == '=' || next == '*' || next == '#' ||
                        next == ';' || next == ':' || next == ' ')
                        break;
                    if (pos + 2 < src.length)
                    {
                        if (src[pos + 1 .. pos + 3] == "{|" ||
                            src[pos + 1 .. pos + 3] == "|}")
                            break;
                    }
                    if (pos + 10 < src.length
                        && src[pos + 1 .. pos + 10] == "#REDIRECT")
                        break;
                }
            }
            pos++;
        }

        if (pos > start)
        {
            const(char)[] content = src[start .. pos].strip;
            if (content.length > 0)
            {
                auto pNode = Node(NodeType.Paragraph);
                uint pIdx = cast(uint) nodes.length;
                nodes ~= pNode;
                uint childStart = cast(uint) nodes.length;
                parseInlineInto(content);
                nodes[pIdx].childStart = childStart;
                nodes[pIdx].childEnd = cast(uint) nodes.length;
            }
        }

        skipNewlines();
    }

    // --- Inline parsing ---

    void parseInlineInto(const(char)[] text)
    {
        if (text.length == 0)
            return;

        size_t i = 0;
        size_t textStart = 0;

        void flushText()
        {
            if (i > textStart)
            {
                auto t = Node(NodeType.Text);
                t.text = text[textStart .. i];
                nodes ~= t;
            }
        }

        while (i < text.length)
        {
            // HTML comment
            if (i + 4 < text.length && text[i .. i + 4] == "<!--")
            {
                flushText();
                size_t end = sliceIndexOf(text[i + 4 .. $], "-->");
                if (end == size_t.max)
                {
                    nodes ~= Node(NodeType.Comment, text[i + 4 .. $]);
                    textStart = text.length;
                    i = text.length;
                }
                else
                {
                    nodes ~= Node(NodeType.Comment, text[i + 4 .. i + 4 + end]);
                    i = i + 4 + end + 3;
                    textStart = i;
                }
                continue;
            }

            // Template {{ ... }}
            if (i + 1 < text.length && text[i] == '{' && text[i + 1] == '{')
            {
                flushText();
                size_t end = findMatchingClose(text, i + 2, "{{", "}}");
                if (end == size_t.max)
                {
                    textStart = i;
                    i = text.length;
                }
                else
                {
                    auto tpl = Node(NodeType.Template);
                    tpl.text = text[i + 2 .. end];
                    nodes ~= tpl;
                    i = end + 2;
                    textStart = i;
                }
                continue;
            }

            // Wikilink [[ ... ]]
            if (i + 1 < text.length && text[i] == '[' && text[i + 1] == '[')
            {
                flushText();
                size_t close = findMatchingClose(text, i + 2, "[[", "]]");
                if (close == size_t.max)
                {
                    textStart = i;
                    i += 2;
                    continue;
                }

                const(char)[] inner = text[i + 2 .. close];
                i = close + 2;
                textStart = i;

                // Category [[Category:...]]
                if (inner.length > 9 && (inner[0 .. 9] == "Category:" || inner[0 .. 9] == "category:"))
                {
                    auto cat = Node(NodeType.Category);
                    auto pipeIdx = sliceIndexOf(inner[9 .. $], "|");
                    cat.text = pipeIdx != size_t.max
                        ? inner[9 .. 9 + pipeIdx].strip
                        : inner[9 .. $].strip;
                    nodes ~= cat;
                    continue;
                }

                // File/Image [[File:...]] [[Image:...]]
                if ((inner.length > 5 && (inner[0 .. 5] == "File:" || inner[0 .. 5] == "file:")) ||
                    (inner.length > 6 && (inner[0 .. 6] == "Image:" || inner[0 .. 6] == "image:")))
                {
                    auto img = Node(NodeType.Image);
                    size_t colon = sliceIndexOf(inner, ":");
                    img.target = colon != size_t.max ? inner[colon + 1 .. $] : inner;
                    // Extract display text (last pipe-separated field).
                    auto pipeIdx = sliceLastIndexOf(inner, "|");
                    if (pipeIdx != size_t.max)
                        img.text = inner[pipeIdx + 1 .. $].strip;
                    nodes ~= img;
                    continue;
                }

                // Regular wikilink
                auto link = Node(NodeType.Link);
                auto pipeIdx = sliceIndexOf(inner, "|");
                if (pipeIdx != size_t.max)
                {
                    link.target = inner[0 .. pipeIdx].strip;
                    link.text = inner[pipeIdx + 1 .. $].strip;
                }
                else
                {
                    link.target = inner.strip;
                    link.text = inner.strip;
                }
                nodes ~= link;
                continue;
            }

            // External link [url text]
            if (text[i] == '[' && (i + 1 >= text.length || text[i + 1] != '['))
            {
                // Check if it looks like a URL.
                if (i + 8 < text.length &&
                    (text[i + 1 .. i + 8] == "http://" ||
                     (i + 9 < text.length && text[i + 1 .. i + 9] == "https://")))
                {
                    flushText();
                    size_t close = sliceIndexOf(text[i + 1 .. $], "]");
                    if (close != size_t.max)
                    {
                        const(char)[] inner = text[i + 1 .. i + 1 + close];
                        auto spaceIdx = sliceIndexOf(inner, " ");
                        auto el = Node(NodeType.ExtLink);
                        if (spaceIdx != size_t.max)
                        {
                            el.target = inner[0 .. spaceIdx];
                            el.text = inner[spaceIdx + 1 .. $].strip;
                        }
                        else
                        {
                            el.target = inner;
                            el.text = inner;
                        }
                        nodes ~= el;
                        i = i + 1 + close + 1;
                        textStart = i;
                        continue;
                    }
                }
            }

            // Bold/italic markup
            if (text[i] == '\'' && i + 1 < text.length && text[i + 1] == '\'')
            {
                flushText();

                int quoteCount = 0;
                size_t qStart = i;
                while (i < text.length && text[i] == '\'')
                {
                    quoteCount++;
                    i++;
                }

                NodeType nt;
                if (quoteCount >= 5)
                    nt = NodeType.BoldItalic;
                else if (quoteCount >= 3)
                    nt = NodeType.Bold;
                else
                    nt = NodeType.Italic;

                // Find matching closing quotes.
                int closeQuotes = quoteCount >= 5 ? 5 : quoteCount >= 3 ? 3 : 2;
                string closeStr;
                if (closeQuotes == 5) closeStr = "'''''";
                else if (closeQuotes == 3) closeStr = "'''";
                else closeStr = "''";

                size_t closeIdx = sliceIndexOf(text[i .. $], closeStr);
                if (closeIdx == size_t.max)
                {
                    // No matching close; treat quotes as text.
                    auto t = Node(NodeType.Text);
                    t.text = text[qStart .. i];
                    nodes ~= t;
                    textStart = i;
                    continue;
                }

                auto fmtNode = Node(nt);
                uint fmtIdx = cast(uint) nodes.length;
                nodes ~= fmtNode;
                uint childStart = cast(uint) nodes.length;
                parseInlineInto(text[i .. i + closeIdx]);
                nodes[fmtIdx].childStart = childStart;
                nodes[fmtIdx].childEnd = cast(uint) nodes.length;

                i = i + closeIdx + closeStr.length;
                textStart = i;
                continue;
            }

            // <ref>...</ref> (inline reference)
            if (i + 4 < text.length && text[i .. i + 4] == "<ref")
            {
                flushText();
                // Self-closing <ref ... />
                size_t tagEnd = sliceIndexOf(text[i .. $], ">");
                if (tagEnd != size_t.max)
                {
                    // Check for self-closing.
                    if (text[i + tagEnd - 1] == '/'
                        || (tagEnd >= 2 && text[i + tagEnd - 1] == ' '
                            && text[i + tagEnd - 2] == '/'))
                    {
                        auto refNode = Node(NodeType.Reference);
                        refNode.text = text[i .. i + tagEnd + 1];
                        nodes ~= refNode;
                        i = i + tagEnd + 1;
                        textStart = i;
                        continue;
                    }

                    size_t contentStart = i + tagEnd + 1;
                    size_t endRef = sliceIndexOf(text[contentStart .. $], "</ref>");
                    if (endRef != size_t.max)
                    {
                        auto refNode = Node(NodeType.Reference);
                        refNode.text = text[contentStart .. contentStart + endRef];
                        nodes ~= refNode;
                        i = contentStart + endRef + 6;
                        textStart = i;
                        continue;
                    }
                }
                // Couldn't parse ref, just skip the '<'
                i++;
                textStart = qStart(i, textStart);
                continue;
            }

            // <br>, <br/>, <br />
            if (i + 3 < text.length && text[i .. i + 3] == "<br")
            {
                flushText();
                size_t tagEnd = sliceIndexOf(text[i .. $], ">");
                if (tagEnd != size_t.max)
                {
                    nodes ~= Node(NodeType.LineBreak);
                    i = i + tagEnd + 1;
                    textStart = i;
                    continue;
                }
            }

            // Generic HTML tags (inline)
            if (text[i] == '<' && i + 1 < text.length && isAlpha(text[i + 1]))
            {
                flushText();
                size_t tagEnd = sliceIndexOf(text[i .. $], ">");
                if (tagEnd != size_t.max)
                {
                    auto ht = Node(NodeType.HtmlTag);
                    ht.text = text[i .. i + tagEnd + 1];
                    nodes ~= ht;
                    i = i + tagEnd + 1;
                    textStart = i;
                    continue;
                }
            }

            // Closing HTML tags
            if (text[i] == '<' && i + 2 < text.length && text[i + 1] == '/')
            {
                flushText();
                size_t tagEnd = sliceIndexOf(text[i .. $], ">");
                if (tagEnd != size_t.max)
                {
                    auto ht = Node(NodeType.HtmlTag);
                    ht.text = text[i .. i + tagEnd + 1];
                    nodes ~= ht;
                    i = i + tagEnd + 1;
                    textStart = i;
                    continue;
                }
            }

            i++;
        }

        // Flush remaining text.
        if (textStart < text.length)
        {
            auto t = Node(NodeType.Text);
            t.text = text[textStart .. text.length];
            nodes ~= t;
        }
    }

    static size_t qStart(size_t i, size_t textStart)
    {
        return i - 1 < textStart ? textStart : textStart;
    }

    // --- Restructuring pass ---
    // After flat parsing, sections only have heading text but no children.
    // Restructure so each Section node owns all subsequent content until the
    // next section of same or higher level.

    void restructure()
    {
        if (nodes.length <= 1)
            return;

        Node[] result;
        result.reserve(nodes.length);
        result ~= Node(NodeType.Document); // new root

        // Collect top-level children, skipping over subtrees.
        uint[] topChildren;
        uint i = 1;
        while (i < cast(uint) nodes.length)
        {
            topChildren ~= i;
            // Skip this node's subtree to find the next top-level node.
            if (nodes[i].hasChildren)
                i = nodes[i].childEnd;
            else
                i++;
        }

        // Rebuild with section nesting.
        rebuildSections(result, topChildren);

        result[0].childStart = 1;
        result[0].childEnd = cast(uint) result.length;

        nodes = result;
    }

    void rebuildSections(ref Node[] result, uint[] indices)
    {
        size_t i = 0;
        while (i < indices.length)
        {
            uint idx = indices[i];

            if (nodes[idx].type != NodeType.Section)
            {
                // Non-section node: deep copy it with its children.
                deepCopy(result, idx);
                i++;
                continue;
            }

            // Section node: collect all following nodes until next section
            // of same or higher level.
            ubyte secLevel = nodes[idx].level;
            uint secResultIdx = cast(uint) result.length;
            auto secCopy = nodes[idx];
            result ~= secCopy;

            uint childStart = cast(uint) result.length;
            i++;

            // Gather body of this section.
            uint[] bodyIndices;
            while (i < indices.length)
            {
                uint bi = indices[i];
                if (nodes[bi].type == NodeType.Section
                    && nodes[bi].level <= secLevel)
                    break;
                bodyIndices ~= bi;
                i++;
            }

            // Recursively rebuild subsections within this section's body.
            rebuildSections(result, bodyIndices);

            result[secResultIdx].childStart = childStart;
            result[secResultIdx].childEnd = cast(uint) result.length;
        }
    }

    void deepCopy(ref Node[] result, uint idx)
    {
        uint newIdx = cast(uint) result.length;
        auto n = nodes[idx];
        result ~= n;

        if (n.childStart < n.childEnd)
        {
            uint newChildStart = cast(uint) result.length;
            // Iterate direct children only, skipping subtrees.
            uint c = n.childStart;
            while (c < n.childEnd)
            {
                deepCopy(result, c);
                if (nodes[c].hasChildren)
                    c = nodes[c].childEnd;
                else
                    c++;
            }
            result[newIdx].childStart = newChildStart;
            result[newIdx].childEnd = cast(uint) result.length;
        }
    }

    // --- Utility ---

    char peek() const
    {
        return src[pos];
    }

    size_t remaining() const
    {
        return src.length - pos;
    }

    bool matchAt(string s) const
    {
        return pos + s.length <= src.length && src[pos .. pos + s.length] == s;
    }

    bool atLineStart() const
    {
        return pos == 0 || (pos > 0 && src[pos - 1] == '\n');
    }

    size_t findLineEnd(size_t from) const
    {
        size_t p = from;
        while (p < src.length && src[p] != '\n')
            p++;
        return p;
    }

    void skipNewlines()
    {
        while (pos < src.length && (src[pos] == '\n' || src[pos] == '\r'))
            pos++;
    }

    void skipComments()
    {
        while (pos + 4 < src.length && src[pos .. pos + 4] == "<!--")
        {
            size_t end = indexOfStr(pos + 4, "-->");
            if (end == size_t.max)
            {
                nodes ~= Node(NodeType.Comment, src[pos + 4 .. $]);
                pos = src.length;
                return;
            }
            nodes ~= Node(NodeType.Comment, src[pos + 4 .. end]);
            pos = end + 3;
            skipNewlines();
        }
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
            if (src[j .. j + s.length] == s) return j;
        return size_t.max;
    }

    // Static helpers for slices (not tied to src).

    static size_t sliceIndexOf(const(char)[] hay, const(char)[] needle)
    {
        if (needle.length == 0) return 0;
        if (hay.length < needle.length) return size_t.max;
        for (size_t j = 0; j + needle.length <= hay.length; j++)
            if (hay[j .. j + needle.length] == needle) return j;
        return size_t.max;
    }

    static size_t sliceLastIndexOf(const(char)[] hay, const(char)[] needle)
    {
        if (needle.length == 0) return hay.length;
        if (hay.length < needle.length) return size_t.max;
        size_t last = size_t.max;
        for (size_t j = 0; j + needle.length <= hay.length; j++)
            if (hay[j .. j + needle.length] == needle) last = j;
        return last;
    }

    static size_t findMatchingClose(const(char)[] text, size_t start,
        const(char)[] open, const(char)[] close)
    {
        int depth = 1;
        size_t j = start;
        while (j < text.length)
        {
            if (j + close.length <= text.length && text[j .. j + close.length] == close)
            {
                depth--;
                if (depth == 0)
                    return j;
                j += close.length;
            }
            else if (j + open.length <= text.length && text[j .. j + open.length] == open)
            {
                depth++;
                j += open.length;
            }
            else
                j++;
        }
        return size_t.max;
    }

    static bool isAlpha(char c) pure nothrow @nogc
    {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
    }
}
