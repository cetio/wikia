module gui.article.render;

import gtk.box;
import gtk.grid;
import gtk.label;
import gtk.types : Orientation, Align;
import gtk.widget : Widget;

import wikia.text.ast;
import wikia.page : Page;

/// Render a Page's AST into GTK widgets appended to `container`.
/// Skips References, Comments, Categories, Templates, Images.
void renderPage(Page page, Box container)
{
    if (page is null)
        return;

    auto doc = page.document();
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

    auto doc = page.document();
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
    string heading = cast(string) section.text;
    if (heading.length > 0)
    {
        if (headingCallback !is null)
            headingCallback(heading, section.level);
        else
        {
            auto label = new Label(heading);
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
            return escapeMarkup(cast(string) node.text);

        case Bold:
            return "<b>"~childrenMarkup(doc, node)~"</b>";

        case Italic:
            return "<i>"~childrenMarkup(doc, node)~"</i>";

        case BoldItalic:
            return "<b><i>"~childrenMarkup(doc, node)~"</i></b>";

        case Link:
            return node.text.length > 0
                ? escapeMarkup(cast(string) node.text)
                : escapeMarkup(cast(string) node.target);

        case ExtLink:
            string display = node.text.length > 0
                ? escapeMarkup(cast(string) node.text)
                : escapeMarkup(cast(string) node.target);
            return `<a href="`~escapeMarkup(cast(string) node.target)~`">`~display~`</a>`;

        case LineBreak:
            return "\n";

        case NoWiki:
            return escapeMarkup(cast(string) node.text);

        case HtmlTag:
            return htmlTagToMarkup(cast(string) node.text);

        case Template:
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
                container.append(makeLabel(escapeMarkup(cast(string) node.text), false));
            break;

        case Bold:
        case Italic:
        case BoldItalic:
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
            auto preLabel = new Label(cast(string) node.text);
            preLabel.addCssClass("article-preformatted");
            preLabel.halign = Align.Start;
            preLabel.xalign = 0;
            preLabel.wrap = false;
            preLabel.hexpand = true;
            preLabel.selectable = true;
            container.append(preLabel);
            break;

        case HorizontalRule:
            auto separator = new Box(Orientation.Horizontal, 0);
            separator.addCssClass("article-hr");
            separator.hexpand = true;
            separator.heightRequest = 1;
            container.append(separator);
            break;

        case BlockQuote:
            auto quoteBox = new Box(Orientation.Vertical, 0);
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

private:

void renderList(ref Document doc, ref const Node list, Box container)
{
    if (!list.hasChildren)
        return;

    auto listBox = new Box(Orientation.Vertical, 2);
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

                Label label = makeLabel(bullet ~ content, true);
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

    auto defBox = new Box(Orientation.Vertical, 2);
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
    if (!table.hasChildren)
        return;

    auto tableBox = new Box(Orientation.Vertical, 0);
    tableBox.addCssClass("article-table");
    tableBox.hexpand = true;

    // Count columns across all rows to size the grid correctly.
    int maxColumns = 0;
    uint scanIdx = table.childStart;
    while (scanIdx < table.childEnd)
    {
        if (doc.nodes[scanIdx].type == NodeType.TableRow && doc.nodes[scanIdx].hasChildren)
        {
            int cols = 0;
            uint cellIdx = doc.nodes[scanIdx].childStart;
            while (cellIdx < doc.nodes[scanIdx].childEnd)
            {
                if (doc.nodes[cellIdx].type == NodeType.TableCell
                    || doc.nodes[cellIdx].type == NodeType.TableHeader)
                    cols++;
                cellIdx = doc.nextSiblingIdx(cellIdx);
            }
            if (cols > maxColumns)
                maxColumns = cols;
        }
        scanIdx = doc.nextSiblingIdx(scanIdx);
    }

    if (maxColumns == 0)
        return;

    // Skip tables where all cells are empty (e.g. reference-only tables).
    bool hasContent = false;
    scanIdx = table.childStart;
    while (scanIdx < table.childEnd && !hasContent)
    {
        if (doc.nodes[scanIdx].type == NodeType.TableRow && doc.nodes[scanIdx].hasChildren)
        {
            uint cellIdx = doc.nodes[scanIdx].childStart;
            while (cellIdx < doc.nodes[scanIdx].childEnd)
            {
                if ((doc.nodes[cellIdx].type == NodeType.TableCell
                    || doc.nodes[cellIdx].type == NodeType.TableHeader)
                    && childrenMarkup(doc, doc.nodes[cellIdx]).length > 0)
                {
                    hasContent = true;
                    break;
                }
                cellIdx = doc.nextSiblingIdx(cellIdx);
            }
        }
        scanIdx = doc.nextSiblingIdx(scanIdx);
    }
    if (!hasContent)
        return;

    auto grid = new Grid();
    grid.addCssClass("article-table-grid");
    grid.hexpand = true;
    grid.columnHomogeneous = true;
    grid.rowSpacing = 0;
    grid.columnSpacing = 0;

    int row = 0;
    uint tableChildIdx = table.childStart;
    while (tableChildIdx < table.childEnd)
    {
        if (doc.nodes[tableChildIdx].type == NodeType.TableCaption)
        {
            auto caption = new Label(cast(string) doc.nodes[tableChildIdx].text);
            caption.addCssClass("article-table-caption");
            caption.halign = Align.Start;
            caption.xalign = 0;
            caption.wrap = true;
            tableBox.append(caption);
            tableChildIdx = doc.nextSiblingIdx(tableChildIdx);
            continue;
        }

        if (doc.nodes[tableChildIdx].type != NodeType.TableRow
            || !doc.nodes[tableChildIdx].hasChildren)
        {
            tableChildIdx = doc.nextSiblingIdx(tableChildIdx);
            continue;
        }

        int col = 0;
        uint cellIdx = doc.nodes[tableChildIdx].childStart;
        while (cellIdx < doc.nodes[tableChildIdx].childEnd)
        {
            if (doc.nodes[cellIdx].type == NodeType.TableCell
                || doc.nodes[cellIdx].type == NodeType.TableHeader)
            {
                string markup = childrenMarkup(doc, doc.nodes[cellIdx]);
                Label cellLabel = makeLabel(markup, true);
                cellLabel.addCssClass("article-table-cell");
                if (doc.nodes[cellIdx].type == NodeType.TableHeader)
                    cellLabel.addCssClass("article-table-header");
                cellLabel.hexpand = true;
                cellLabel.halign = Align.Fill;
                cellLabel.valign = Align.Start;
                grid.attach(cellLabel, col, row, 1, 1);
                col++;
            }
            cellIdx = doc.nextSiblingIdx(cellIdx);
        }
        row++;
        tableChildIdx = doc.nextSiblingIdx(tableChildIdx);
    }

    tableBox.append(grid);
    container.append(tableBox);
}

string childrenMarkup(ref Document doc, ref const Node parent)
{
    if (!parent.hasChildren)
    {
        if (parent.text.length > 0)
            return escapeMarkup(cast(string) parent.text);
        return "";
    }

    string result;
    uint childIdx = parent.childStart;
    while (childIdx < parent.childEnd)
    {
        result ~= nodeToMarkup(doc, doc.nodes[childIdx]);
        childIdx = doc.nextSiblingIdx(childIdx);
    }
    return result;
}

Label makeLabel(string text, bool markup)
{
    if (markup)
        text = sanitizePangoMarkup(text);
    auto label = new Label(text);
    label.addCssClass("report-body-text");
    label.halign = Align.Start;
    label.xalign = 0;
    label.wrap = true;
    label.hexpand = true;
    label.selectable = true;
    if (markup)
        label.useMarkup = true;
    return label;
}

/// Ensure all Pango-safe tags in the markup are properly balanced.
/// Close any unclosed tags and remove orphan closing tags.
string sanitizePangoMarkup(string text)
{
    if (text.length == 0)
        return text;

    // Track open tag stack.
    string[] openStack;
    string result;
    result.reserve(text.length + 32);

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
                string name = text[nameStart .. nameEnd];
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
                                    result ~= "</" ~ openStack[$ - 1] ~ ">";
                                    openStack = openStack[0 .. $ - 1];
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
                            result ~= "<" ~ name ~ ">";
                            openStack ~= name;
                        }
                        idx = closeAngle;
                        continue;
                    }
                }
            }
        }
        result ~= text[idx];
    }

    // Close any remaining unclosed tags.
    for (size_t s = openStack.length; s > 0; s--)
        result ~= "</" ~ openStack[s - 1] ~ ">";

    return result;
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
    string name = tag[nameStart .. nameEnd];

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
        if (text[nameStart .. nameEnd] != tag)
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
    bool needsWork = false;
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

    string result;
    result.reserve(text.length + 32);
    for (size_t idx = 0; idx < text.length; idx++)
    {
        if (text[idx] == '&')
        {
            // Decode common HTML entities before escaping.
            if (idx + 5 < text.length && text[idx .. idx + 6] == "&nbsp;")
            {
                result ~= ' ';
                idx += 5;
            }
            else if (idx + 6 < text.length && text[idx .. idx + 7] == "&ndash;")
            {
                result ~= '\u2013';
                idx += 6;
            }
            else if (idx + 6 < text.length && text[idx .. idx + 7] == "&mdash;")
            {
                result ~= '\u2014';
                idx += 6;
            }
            else
                result ~= "&amp;";
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
                string name = text[nameStart .. nameEnd];
                result ~= closing ? ("</" ~ name ~ ">") : ("<" ~ name ~ ">");
                idx += tagLen - 1;
            }
            else
                result ~= "&lt;";
        }
        else if (text[idx] == '>')
            result ~= "&gt;";
        else
            result ~= text[idx];
    }
    return result;
}
