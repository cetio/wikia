module gui.article.render;

import std.conv : to;
import std.string : toLower, strip, indexOf;
import std.uni : toUpper;

import gtk.box;
import gtk.label;
import gtk.types : Orientation, Align;
import gtk.widget : Widget;

import wikia.text.ast;
import wikia.page : Page;
import gui.article.table : Table;

/// Render a Page's AST into GTK widgets appended to `container`.
/// Skips References, Comments, Categories, Templates, Images.
void renderPage(Page page, Box container)
{
    if (page is null)
        return;

    Document doc = page.document();
    if (doc.nodes.length == 0)
        return;

    // Render preamble nodes.
    foreach (ref node; doc.preamble())
        renderNode(doc, node, container);

    // Render top-level sections.
    foreach (ref node; doc.sections())
        renderSection(doc, node, container, null);
}

/// Render preamble nodes only (everything before first section).
void renderPreamble(Page page, Box container)
{
    if (page is null)
        return;

    Document doc = page.document();
    if (doc.nodes.length == 0)
        return;

    foreach (ref node; doc.preamble())
        renderNode(doc, node, container);
}

/// Render section content into a container. If `headingCallback` is
/// provided, it is called with the heading text and level instead of
/// creating a default heading label.
void renderSection(
    ref Document doc,
    ref const Node section,
    Box container,
    void delegate(string heading, int level) headingCallback
)
{
    if (section.type != NodeType.Section)
        return;

    // Heading.
    string heading = section.text;
    if (heading.length > 0)
    {
        if (headingCallback !is null)
            headingCallback(heading, section.level);
        else
        {
            Label label = new Label(heading.toUpper);
            label.addCssClass(section.level <= 2 ? "article-heading" : "article-subheading");
            label.halign = Align.Start;
            label.xalign = 0;
            label.wrap = true;
            label.hexpand = true;
            container.append(label);
        }
    }

    // Section body.
    if (section.hasChildren)
    {
        uint childIdx = section.childStart;
        while (childIdx < section.childEnd)
        {
            if (doc.nodes[childIdx].type == NodeType.Section)
                renderSection(doc, doc.nodes[childIdx], container, headingCallback);
            else
                renderNode(doc, doc.nodes[childIdx], container);
            childIdx = doc.nextSiblingIdx(childIdx);
        }
    }
}

/// Extract Pango markup from an inline node subtree. Used for
/// labels that support markup (bold, italic, links).
string nodeToMarkup(ref Document doc, ref const Node node)
{
    final switch (node.type) with (NodeType)
    {
        case Text:
            return escapeMarkup(node.text);

        case Styled:
            string inner = childrenMarkup(doc, node);
            if (node.hasFlag(NodeFlags.Bold))
                inner = "<b>"~inner~"</b>";
            if (node.hasFlag(NodeFlags.Italic))
                inner = "<i>"~inner~"</i>";
            return inner;

        case Link:
            return node.text.length > 0
                ? escapeMarkup(node.text)
                : escapeMarkup(node.target);

        case ExtLink:
            string display = node.text.length > 0
                ? escapeMarkup(node.text)
                : escapeMarkup(node.target);
            return `<a href="`~escapeMarkup(node.target)~`">`~display~`</a>`;

        case LineBreak:
            return "\n";

        case NoWiki:
            return escapeMarkup(node.text);

        case HtmlTag:
            return htmlTagToMarkup(node.text);

        case Template:
            return templateToMarkup(node.text);

        case Reference:
        case Comment:
        case Category:
        case Image:
        case Redirect:
        case Math:
            return "";

        case Paragraph:
        case Section:
        case Document:
        case UnorderedList:
        case OrderedList:
        case ListItem:
        case DefinitionList:
        case DefinitionTerm:
        case DefinitionDesc:
        case Table:
        case TableRow:
        case TableHeader:
        case TableCell:
        case TableCaption:
        case Preformatted:
        case HorizontalRule:
        case BlockQuote:
            return childrenMarkup(doc, node);
    }
}

/// Render a single AST node into GTK widgets.
void renderNode(ref Document doc, ref const Node node, Box container)
{
    final switch (node.type) with (NodeType)
    {
        case Paragraph:
            string markup = childrenMarkup(doc, node);
            if (markup.length > 0)
                container.append(makeLabel(markup, true));
            break;

        case Text:
            if (node.text.length > 0)
                container.append(makeLabel(escapeMarkup(node.text), false));
            break;

        case Styled:
        case Link:
        case ExtLink:
        case NoWiki:
            string markup = nodeToMarkup(doc, node);
            if (markup.length > 0)
                container.append(makeLabel(markup, true));
            break;

        case UnorderedList:
        case OrderedList:
            renderList(doc, node, container);
            break;

        case DefinitionList:
            renderDefinitionList(doc, node, container);
            break;

        case Table:
            renderTable(doc, node, container);
            break;

        case Preformatted:
            Label preLabel = new Label(node.text);
            preLabel.addCssClass("article-preformatted");
            preLabel.halign = Align.Start;
            preLabel.xalign = 0;
            preLabel.wrap = false;
            preLabel.hexpand = true;
            preLabel.selectable = true;
            container.append(preLabel);
            break;

        case HorizontalRule:
            Box separator = new Box(Orientation.Horizontal, 0);
            separator.addCssClass("article-hr");
            separator.hexpand = true;
            separator.heightRequest = 1;
            container.append(separator);
            break;

        case BlockQuote:
            Box quoteBox = new Box(Orientation.Vertical, 0);
            quoteBox.addCssClass("article-blockquote");
            quoteBox.hexpand = true;
            quoteBox.marginStart = 24;
            if (node.hasChildren)
            {
                uint childIdx = node.childStart;
                while (childIdx < node.childEnd)
                {
                    renderNode(doc, doc.nodes[childIdx], quoteBox);
                    childIdx = doc.nextSiblingIdx(childIdx);
                }
            }
            container.append(quoteBox);
            break;

        case Section:
            // Sections handled separately via renderSection.
            break;

        case LineBreak:
            break;

        // Skip non-visual / inline-only nodes.
        case Reference:
        case Template:
        case Comment:
        case Category:
        case Image:
        case Redirect:
        case HtmlTag:
        case Math:
        case Document:
        case ListItem:
        case DefinitionTerm:
        case DefinitionDesc:
        case TableRow:
        case TableHeader:
        case TableCell:
        case TableCaption:
            break;
    }
}

/// Extract Pango markup from all children of a node.
string childrenMarkup(ref Document doc, ref const Node parent)
{
    if (!parent.hasChildren)
    {
        if (parent.text.length > 0)
            return escapeMarkup(parent.text);
        return "";
    }

    string ret;
    uint childIdx = parent.childStart;
    while (childIdx < parent.childEnd)
    {
        ret ~= nodeToMarkup(doc, doc.nodes[childIdx]);
        childIdx = doc.nextSiblingIdx(childIdx);
    }
    return ret;
}

Label makeLabel(string text, bool markup)
{
    if (markup)
        text = sanitizePangoMarkup(text);
    Label lbl = new Label(text);
    lbl.addCssClass("report-body-text");
    lbl.halign = Align.Start;
    lbl.xalign = 0;
    lbl.wrap = true;
    lbl.hexpand = true;
    lbl.selectable = true;
    if (markup)
        lbl.useMarkup = true;
    return lbl;
}

private:

void renderList(ref Document doc, ref const Node list, Box container)
{
    if (!list.hasChildren)
        return;

    Box listBox = new Box(Orientation.Vertical, 2);
    listBox.addCssClass("article-list");
    listBox.hexpand = true;
    listBox.marginStart = 16;

    bool ordered = list.type == NodeType.OrderedList;
    int counter = 1;

    uint itemIdx = list.childStart;
    while (itemIdx < list.childEnd)
    {
        if (doc.nodes[itemIdx].type == NodeType.ListItem)
        {
            string content = childrenMarkup(doc, doc.nodes[itemIdx]);
            if (content.length > 0)
            {
                string bullet = "\u2022 ";
                if (ordered)
                {
                    import std.conv : to;
                    bullet = counter.to!string~". ";
                    counter++;
                }

                Label label = makeLabel(bullet~content, true);
                label.marginStart = cast(int)(
                    doc.nodes[itemIdx].level > 1
                        ? (doc.nodes[itemIdx].level - 1) * 12 : 0);
                listBox.append(label);
            }
        }
        itemIdx = doc.nextSiblingIdx(itemIdx);
    }

    container.append(listBox);
}

void renderDefinitionList(ref Document doc, ref const Node defList, Box container)
{
    if (!defList.hasChildren)
        return;

    Box defBox = new Box(Orientation.Vertical, 2);
    defBox.addCssClass("article-list");
    defBox.hexpand = true;
    defBox.marginStart = 16;

    uint defIdx = defList.childStart;
    while (defIdx < defList.childEnd)
    {
        string markup = childrenMarkup(doc, doc.nodes[defIdx]);
        if (doc.nodes[defIdx].type == NodeType.DefinitionTerm)
        {
            defBox.append(makeLabel("<b>"~markup~"</b>", true));
        }
        else if (doc.nodes[defIdx].type == NodeType.DefinitionDesc)
        {
            Label label = makeLabel(markup, true);
            label.marginStart = 12;
            defBox.append(label);
        }
        defIdx = doc.nextSiblingIdx(defIdx);
    }

    container.append(defBox);
}

void renderTable(ref Document doc, ref const Node table, Box container)
{
    import std.string : toLower, strip;

    if (!table.hasChildren)
        return;

    // First pass: collect rows as markup strings, track headers.
    string[][] rowData;
    bool[] rowIsHeader;
    string caption;

    uint ti = table.childStart;
    while (ti < table.childEnd)
    {
        if (doc.nodes[ti].type == NodeType.TableCaption)
        {
            caption = childrenMarkup(doc, doc.nodes[ti]);
            if (caption.length == 0)
                caption = doc.nodes[ti].text;
            ti = doc.nextSiblingIdx(ti);
            continue;
        }

        if (doc.nodes[ti].type != NodeType.TableRow
            || !doc.nodes[ti].hasChildren)
        {
            ti = doc.nextSiblingIdx(ti);
            continue;
        }

        string[] cells;
        bool hdr = true;

        uint ci = doc.nodes[ti].childStart;
        while (ci < doc.nodes[ti].childEnd)
        {
            if (doc.nodes[ci].type == NodeType.TableCell
                || doc.nodes[ci].type == NodeType.TableHeader)
            {
                cells ~= childrenMarkup(doc, doc.nodes[ci]);
                if (doc.nodes[ci].type != NodeType.TableHeader)
                    hdr = false;
            }
            ci = doc.nextSiblingIdx(ci);
        }

        if (cells.length > 0)
        {
            rowData ~= cells;
            rowIsHeader ~= hdr;
        }
        ti = doc.nextSiblingIdx(ti);
    }

    if (rowData.length == 0)
        return;

    // Detect columns to drop: reference headers, entirely empty.
    int maxCols;
    foreach (row; rowData)
        if (cast(int) row.length > maxCols)
            maxCols = cast(int) row.length;

    bool[] dropCol = new bool[maxCols];

    // Mark ref-like header columns.
    enum string[5] refNames = ["ref", "refs", "references", "ref.", "notes"];
    foreach (ri, row; rowData)
    {
        if (!rowIsHeader[ri]) continue;
        foreach (ci, cell; row)
        {
            string lower = cell.strip.toLower;
            foreach (rn; refNames)
                if (lower == rn) { dropCol[ci] = true; break; }
        }
    }

    // Drop columns that are entirely empty across all rows.
    foreach (ci; 0..maxCols)
    {
        if (dropCol[ci]) continue;
        bool allEmpty = true;
        foreach (row; rowData)
        {
            if (ci < row.length && row[ci].strip.length > 0)
            {
                allEmpty = false;
                break;
            }
        }
        if (allEmpty)
            dropCol[ci] = true;
    }

    // Check if any visible content remains.
    bool hasContent;
    foreach (row; rowData)
    {
        foreach (ci, cell; row)
        {
            if (ci < dropCol.length && dropCol[ci]) continue;
            if (cell.strip.length > 0) { hasContent = true; break; }
        }
        if (hasContent) break;
    }
    if (!hasContent)
        return;

    Table tbl = new Table();
    if (caption.length > 0)
        tbl.setCaption(sanitizePangoMarkup(caption), true);

    foreach (ri, row; rowData)
    {
        Widget[] filtered;
        foreach (ci, cell; row)
        {
            if (ci < dropCol.length && dropCol[ci])
                continue;
            Label lbl = makeLabel(cell, true);
            lbl.wrap = false;
            lbl.addCssClass("article-table-cell");
            if (rowIsHeader[ri])
                lbl.addCssClass("article-table-header");
            filtered ~= lbl;
        }
        if (filtered.length > 0)
            tbl.addRow(filtered, rowIsHeader[ri]);
    }

    container.append(tbl);
}

/// Ensure all Pango-safe tags in the markup are properly balanced.
/// Close any unclosed tags and remove orphan closing tags.
string sanitizePangoMarkup(string text)
{
    if (text.length == 0)
        return text;

    // Track open tag stack.
    string[] openStack;
    string ret;
    ret.reserve(text.length + 32);

    for (size_t idx = 0; idx < text.length; idx++)
    {
        if (text[idx] == '<' && idx + 1 < text.length)
        {
            bool closing = text[idx + 1] == '/';
            size_t nameStart = idx + (closing ? 2 : 1);
            size_t nameEnd = nameStart;
            while (nameEnd < text.length && text[nameEnd] != '>'
                && text[nameEnd] != ' ' && text[nameEnd] != '/')
                nameEnd++;

            // Find the end of the tag.
            size_t closeAngle = nameEnd;
            while (closeAngle < text.length && text[closeAngle] != '>')
                closeAngle++;

            if (closeAngle < text.length && nameEnd > nameStart)
            {
                string name = text[nameStart..nameEnd];
                bool isPango = false;
                foreach (tag; pangoTags)
                {
                    if (name == tag)
                    {
                        isPango = true;
                        break;
                    }
                }

                if (isPango)
                {
                    if (closing)
                    {
                        // Only emit closing tag if matching open tag exists.
                        bool found = false;
                        for (size_t s = openStack.length; s > 0; s--)
                        {
                            if (openStack[s - 1] == name)
                            {
                                // Close all tags down to the match.
                                while (openStack.length >= s)
                                {
                                    ret ~= "</"~openStack[$ - 1]~">";
                                    openStack = openStack[0..$ - 1];
                                }
                                found = true;
                                break;
                            }
                        }
                        // If no match, skip orphan closing tag.
                        idx = closeAngle;
                        continue;
                    }
                    else
                    {
                        // Self-closing check.
                        bool selfClosing = closeAngle > 0 && text[closeAngle - 1] == '/';
                        if (!selfClosing)
                        {
                            ret ~= "<"~name~">";
                            openStack ~= name;
                        }
                        idx = closeAngle;
                        continue;
                    }
                }
            }
        }
        ret ~= text[idx];
    }

    // Close any remaining unclosed tags.
    for (size_t s = openStack.length; s > 0; s--)
        ret ~= "</"~openStack[s - 1]~">";

    return ret;
}

/// Extract display text from known templates, empty for others.
/// abbrlink and abbr templates use the first param as the abbreviation.
string templateToMarkup(string text)
{
    import std.string : indexOf;

    if (text.length == 0)
        return "";

    // Find template name (text before first |).
    ptrdiff_t pipePos = text.indexOf('|');
    if (pipePos < 0)
        return "";

    string name = text[0..pipePos];
    if (name == "abbrlink" || name == "abbr")
    {
        // First param is the display abbreviation.
        string rest = text[pipePos + 1..$];
        ptrdiff_t nextPipe = rest.indexOf('|');
        string display = nextPipe >= 0 ? rest[0..nextPipe] : rest;
        return escapeMarkup(display);
    }
    return "";
}

/// Convert a recognized HTML tag to its Pango markup equivalent.
/// Unrecognized tags are dropped (return "").
string htmlTagToMarkup(string tag)
{
    if (tag.length < 3)
        return "";

    // Check if this is a closing tag.
    bool closing = tag.length >= 4 && tag[1] == '/';

    // Extract the tag name (between < or </ and > or space).
    size_t nameStart = closing ? 2 : 1;
    size_t nameEnd = nameStart;
    while (nameEnd < tag.length && tag[nameEnd] != '>' && tag[nameEnd] != ' ' && tag[nameEnd] != '/')
        nameEnd++;
    string name = tag[nameStart..nameEnd];

    // Pango supports <sub>, <sup>, <b>, <i>, <u>, <s>, <small>, <big>, <tt>.
    switch (name)
    {
        case "sub":   return closing ? "</sub>" : "<sub>";
        case "sup":   return closing ? "</sup>" : "<sup>";
        case "small": return closing ? "</small>" : "<small>";
        case "big":   return closing ? "</big>" : "<big>";
        case "tt":    return closing ? "</tt>" : "<tt>";
        case "u":     return closing ? "</u>" : "<u>";
        case "s":     return closing ? "</s>" : "<s>";
        case "b":     return closing ? "</b>" : "<b>";
        case "i":     return closing ? "</i>" : "<i>";
        default:      return "";
    }
}

/// Tags that Pango supports natively and should be preserved
/// through escaping rather than converted to &lt;/&gt;.
immutable string[] pangoTags = [
    "sub", "sup", "small", "big", "b", "i", "s", "u", "tt",
];

/// Check if text at position `idx` starts with a known Pango-safe
/// HTML tag (opening or closing). Returns the length of the tag
/// including angle brackets, or 0 if not a recognized tag.
size_t matchPangoTag(string text, size_t idx)
{
    if (idx >= text.length || text[idx] != '<')
        return 0;

    bool closing = (idx + 1 < text.length && text[idx + 1] == '/');
    size_t nameStart = idx + (closing ? 2 : 1);

    foreach (tag; pangoTags)
    {
        size_t nameEnd = nameStart + tag.length;
        if (nameEnd > text.length)
            continue;
        if (text[nameStart..nameEnd] != tag)
            continue;
        // Must be followed by '>' or ' ' or '/' for opening tags.
        if (nameEnd < text.length
            && (text[nameEnd] == '>' || text[nameEnd] == ' ' || text[nameEnd] == '/'))
        {
            // Find the closing '>'.
            size_t closeAngle = nameEnd;
            while (closeAngle < text.length && text[closeAngle] != '>')
                closeAngle++;
            if (closeAngle < text.length)
                return closeAngle - idx + 1;
        }
        // Exact match with just ">"
        if (nameEnd < text.length && text[nameEnd] == '>')
            return nameEnd - idx + 1;
    }
    return 0;
}

string escapeMarkup(string text)
{
    if (text is null || text.length == 0)
        return "";

    // Check if any escaping or entity decoding is needed.
    bool needsWork;
    foreach (ch; text)
    {
        if (ch == '&' || ch == '<' || ch == '>')
        {
            needsWork = true;
            break;
        }
    }
    if (!needsWork)
        return text;

    string ret;
    ret.reserve(text.length + 32);
    for (size_t idx = 0; idx < text.length; idx++)
    {
        if (text[idx] == '&')
        {
            // Preserve already-escaped XML entities, decode others.
            if (idx + 3 < text.length && text[idx..idx + 4] == "&gt;")
            {
                ret ~= "&gt;";
                idx += 3;
            }
            else if (idx + 3 < text.length && text[idx..idx + 4] == "&lt;")
            {
                ret ~= "&lt;";
                idx += 3;
            }
            else if (idx + 4 < text.length && text[idx..idx + 5] == "&amp;")
            {
                ret ~= "&amp;";
                idx += 4;
            }
            else if (idx + 5 < text.length && text[idx..idx + 6] == "&nbsp;")
            {
                ret ~= ' ';
                idx += 5;
            }
            else if (idx + 6 < text.length && text[idx..idx + 7] == "&ndash;")
            {
                ret ~= '\u2013';
                idx += 6;
            }
            else if (idx + 6 < text.length && text[idx..idx + 7] == "&mdash;")
            {
                ret ~= '\u2014';
                idx += 6;
            }
            else if (idx + 6 < text.length && text[idx..idx + 7] == "&minus;")
            {
                ret ~= '\u2212';
                idx += 6;
            }
            else
                ret ~= "&amp;";
        }
        else if (text[idx] == '<')
        {
            // Preserve recognized Pango-safe tags.
            size_t tagLen = matchPangoTag(text, idx);
            if (tagLen > 0)
            {
                // Output a normalized tag: just <name> or </name>.
                bool closing = text[idx + 1] == '/';
                size_t nameStart = idx + (closing ? 2 : 1);
                size_t nameEnd = nameStart;
                while (nameEnd < text.length && text[nameEnd] != '>'
                    && text[nameEnd] != ' ' && text[nameEnd] != '/')
                    nameEnd++;
                string name = text[nameStart..nameEnd];
                ret ~= closing ? ("</"~name~">") : ("<"~name~">");
                idx += tagLen - 1;
            }
            else
                ret ~= "&lt;";
        }
        else if (text[idx] == '>')
            ret ~= "&gt;";
        else
            ret ~= text[idx];
    }
    return ret;
}
