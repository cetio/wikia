module wikia.text.wiki.didactic;

import std.string : indexOf, strip;

import wikia.text.ast;
import wikia.text.wiki : WikitextParser;
import wikia.text.wiki.semantic : parseInlineInto;

/// ---- (four or more dashes)
void parseHorizontalRule(ref WikitextParser p)
{
    size_t end = p.pos + 4;
    while (end < p.src.length && p.src[end] == '-')
        end++;
    p.nodes ~= Node(NodeType.HorizontalRule);
    p.pos = end;
    p.skipNewlines();
}

/// {| ... |} table markup.
void parseTable(ref WikitextParser p)
{
    p.pos += 2;
    size_t lineEnd = p.findLineEnd(p.pos);
    p.pos = lineEnd;
    p.skipNewlines();

    uint tableIdx = cast(uint) p.nodes.length;
    p.nodes ~= Node(NodeType.Table);
    uint firstChild = cast(uint) p.nodes.length;

    while (p.pos < p.src.length)
    {
        if (p.remaining() >= 2 && p.src[p.pos..p.pos + 2] == "|}")
        {
            p.pos += 2;
            p.skipNewlines();
            break;
        }

        // Caption |+
        if (p.remaining() >= 2 && p.src[p.pos..p.pos + 2] == "|+")
        {
            p.pos += 2;
            lineEnd = p.findLineEnd(p.pos);
            string capText = p.src[p.pos..lineEnd].strip;
            uint capIdx = cast(uint) p.nodes.length;
            p.nodes ~= Node(NodeType.TableCaption);
            uint capChildStart = cast(uint) p.nodes.length;
            parseInlineInto(p, capText);
            p.nodes[capIdx].childStart = capChildStart;
            p.nodes[capIdx].childEnd = cast(uint) p.nodes.length;
            p.pos = lineEnd;
            p.skipNewlines();
            continue;
        }

        // Row separator |-
        if (p.remaining() >= 2 && p.src[p.pos..p.pos + 2] == "|-")
        {
            p.pos += 2;
            lineEnd = p.findLineEnd(p.pos);
            p.pos = lineEnd;
            p.skipNewlines();
            parseTableRow(p);
            continue;
        }

        // Cells without explicit row start (first row).
        if (p.peek() == '!' || p.peek() == '|')
        {
            parseTableRow(p);
            continue;
        }

        // Skip unrecognized lines inside table.
        lineEnd = p.findLineEnd(p.pos);
        p.pos = lineEnd;
        p.skipNewlines();
    }

    p.nodes[tableIdx].childStart = firstChild;
    p.nodes[tableIdx].childEnd = cast(uint) p.nodes.length;
}

void parseTableRow(ref WikitextParser p)
{
    uint rowIdx = cast(uint) p.nodes.length;
    p.nodes ~= Node(NodeType.TableRow);
    uint firstChild = cast(uint) p.nodes.length;

    while (p.pos < p.src.length)
    {
        if (p.remaining() >= 2
            && (p.src[p.pos..p.pos + 2] == "|}" || p.src[p.pos..p.pos + 2] == "|-"))
            break;

        bool isHeader = (p.peek() == '!');
        if (p.peek() == '|' || p.peek() == '!')
        {
            p.pos++;
            parseTableCells(p, isHeader);
        }
        else
            break;
    }

    p.nodes[rowIdx].childStart = firstChild;
    p.nodes[rowIdx].childEnd = cast(uint) p.nodes.length;
}

void parseTableCells(ref WikitextParser p, bool isHeader)
{
    size_t lineEnd = p.findLineEnd(p.pos);
    string line = p.src[p.pos..lineEnd];
    p.pos = lineEnd;
    p.skipNewlines();

    // Collect continuation lines.
    while (p.pos < p.src.length)
    {
        if (p.remaining() >= 2
            && (p.src[p.pos..p.pos + 2] == "|}"
                || p.src[p.pos..p.pos + 2] == "|-"
                || p.src[p.pos..p.pos + 2] == "|+"))
            break;
        if (p.peek() == '|' || p.peek() == '!')
            break;

        lineEnd = p.findLineEnd(p.pos);
        line = line~"\n"~p.src[p.pos..lineEnd];
        p.pos = lineEnd;
        p.skipNewlines();
    }

    string sep = isHeader ? "!!" : "||";
    size_t cellStart = 0;

    while (cellStart < line.length)
    {
        ptrdiff_t sepIdx = line[cellStart..$].indexOf(sep);
        string cellText;
        if (sepIdx < 0)
        {
            cellText = line[cellStart..$];
            cellStart = line.length;
        }
        else
        {
            cellText = line[cellStart..cellStart + sepIdx];
            cellStart += sepIdx + sep.length;
        }

        ptrdiff_t pipeIdx = findAttributePipe(cellText);
        if (pipeIdx >= 0)
            cellText = cellText[pipeIdx + 1..$];

        NodeType cellType = isHeader ? NodeType.TableHeader : NodeType.TableCell;
        uint cellIdx = cast(uint) p.nodes.length;
        p.nodes ~= Node(cellType);
        uint inlineStart = cast(uint) p.nodes.length;
        parseInlineInto(p, cellText.strip);
        p.nodes[cellIdx].childStart = inlineStart;
        p.nodes[cellIdx].childEnd = cast(uint) p.nodes.length;
    }
}

/// Find the attribute-separating '|' in cell text, skipping over
/// pipes inside [[ ]], {{ }}, or angle-bracket markup.
ptrdiff_t findAttributePipe(string text)
{
    int bracketDepth = 0;
    int braceDepth = 0;
    int angleDepth = 0;

    for (size_t j = 0; j < text.length; j++)
    {
        if (j + 1 < text.length && text[j] == '[' && text[j + 1] == '[')
        {
            bracketDepth++;
            j++;
            continue;
        }
        if (j + 1 < text.length && text[j] == ']' && text[j + 1] == ']')
        {
            if (bracketDepth > 0) bracketDepth--;
            j++;
            continue;
        }
        if (j + 1 < text.length && text[j] == '{' && text[j + 1] == '{')
        {
            braceDepth++;
            j++;
            continue;
        }
        if (j + 1 < text.length && text[j] == '}' && text[j + 1] == '}')
        {
            if (braceDepth > 0) braceDepth--;
            j++;
            continue;
        }
        if (text[j] == '<') { angleDepth++; continue; }
        if (text[j] == '>') { if (angleDepth > 0) angleDepth--; continue; }

        if (text[j] == '|' && bracketDepth == 0
            && braceDepth == 0 && angleDepth == 0)
            return cast(ptrdiff_t) j;
    }
    return -1;
}

/// Generic HTML block element: <blockquote>...</blockquote> etc.
void parseHtmlBlock(ref WikitextParser p, string tag, NodeType nodeType)
{
    ptrdiff_t tagEnd = p.src[p.pos..$].indexOf('>');
    if (tagEnd < 0)
    {
        p.pos = p.src.length;
        return;
    }
    p.pos += tagEnd + 1;

    string closeTag = "</"~tag~">";
    ptrdiff_t endIdx = p.src[p.pos..$].indexOf(closeTag);
    if (endIdx < 0)
    {
        Node blockNode = Node(nodeType);
        blockNode.text = p.src[p.pos..$];
        p.nodes ~= blockNode;
        p.pos = p.src.length;
    }
    else
    {
        size_t absEnd = p.pos + endIdx;
        uint blockIdx = cast(uint) p.nodes.length;
        p.nodes ~= Node(nodeType);
        uint childStart = cast(uint) p.nodes.length;
        parseInlineInto(p, p.src[p.pos..absEnd]);
        p.nodes[blockIdx].childStart = childStart;
        p.nodes[blockIdx].childEnd = cast(uint) p.nodes.length;
        p.pos = absEnd + closeTag.length;
    }
}
