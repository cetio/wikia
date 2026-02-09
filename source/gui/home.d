module gui.home;

import std.stdio : writeln;
import std.conv : to;

import gtk.box;
import gtk.label;
import gtk.button;
import gtk.search_entry;
import gtk.list_box;
import gtk.list_box_row;
import gtk.overlay;
import gtk.types : Orientation, Align;

import gui.background : Background;
import wikia.pubchem;

class Homepage : Box
{
private:
    SearchEntry searchEntry;
    ListBox suggestionList;
    Box loadingDots;
    Compound[] pendingSimilarCompounds;
    bool isLoading;
    Compound lastSearchCompound;

    Box buildContent()
    {
        Box content = new Box(Orientation.Vertical, 0);
        content.addCssClass("homepage-content");
        content.hexpand = false;
        content.halign = Align.Center;
        content.valign = Align.Start;

        Box headerBox = new Box(Orientation.Vertical, 0);
        headerBox.halign = Align.Center;
        headerBox.valign = Align.Start;

        headerBox.append(buildLogo());
        headerBox.append(buildTagline());
        headerBox.append(buildSearch());

        Box scrollableBox = new Box(Orientation.Vertical, 0);
        scrollableBox.addCssClass("search-results-container");
        scrollableBox.hexpand = true;
        scrollableBox.vexpand = true;

        suggestionList = new ListBox();
        suggestionList.addCssClass("search-results-container");
        suggestionList.connectRowActivated(&onRowActivated);
        suggestionList.visible = false;
        scrollableBox.append(suggestionList);

        content.append(headerBox);
        content.append(scrollableBox);
        content.append(buildLinks());

        return content;
    }

    Box buildLogo()
    {
        Box logoBox = new Box(Orientation.Horizontal, 0);
        logoBox.halign = Align.Center;

        Label logoW = new Label("Wik");
        logoW.addCssClass("homepage-logo");

        Label logoI = new Label("ia");
        logoI.addCssClass("homepage-logo");
        logoI.addCssClass("homepage-logo-accent");

        logoBox.append(logoW);
        logoBox.append(logoI);
        return logoBox;
    }

    Label buildTagline()
    {
        Label tagline = new Label("The free chemical compound database");
        tagline.addCssClass("homepage-tagline");
        tagline.halign = Align.Center;
        return tagline;
    }

    Box buildSearch()
    {
        Box searchBox = new Box(Orientation.Horizontal, 0);
        searchBox.addCssClass("homepage-search-box");
        searchBox.halign = Align.Center;
        searchBox.widthRequest = 600;

        searchEntry = new SearchEntry();
        searchEntry.placeholderText = "Search for a compound...";
        searchEntry.addCssClass("homepage-search-entry");
        searchEntry.hexpand = true;
        searchEntry.halign = Align.Fill;
        searchEntry.connectActivate(&onSearchActivated);
        searchBox.append(searchEntry);

        Button searchBtn = new Button();
        searchBtn.label = "Search";
        searchBtn.addCssClass("homepage-search-button");
        searchBtn.connectClicked(&onSearchBtnClicked);
        searchBox.append(searchBtn);

        return searchBox;
    }

    Box buildLinks()
    {
        Box linksBox = new Box(Orientation.Horizontal, 16);
        linksBox.addCssClass("homepage-links");
        linksBox.halign = Align.Center;
        linksBox.marginTop = 24;

        Label linkText = new Label("Powered by");
        Label pubchemLink = new Label("PubChem");
        pubchemLink.addCssClass("homepage-link");

        linksBox.append(linkText);
        linksBox.append(pubchemLink);
        return linksBox;
    }    

    void updatePrimaryResultCompletion()
    {
        if (suggestionList.getFirstChild() !is null)
        {
            auto primaryRow = cast(ListBoxRow)suggestionList.getFirstChild();
            if (primaryRow !is null)
            {
                auto compound = lastSearchCompound;
                if (compound !is null)
                    primaryRow.setChild(buildResultRow(compound, true, false));
            }
        }
    }

    void showLoadingDots()
    {
        if (!isLoading) return;
        
        loadingDots = new Box(Orientation.Horizontal, 4);
        loadingDots.addCssClass("loading-dots");
        loadingDots.halign = Align.Center;
        
        auto dot1 = new Label(".");
        dot1.addCssClass("dot");
        auto dot2 = new Label(".");
        dot2.addCssClass("dot");
        auto dot3 = new Label(".");
        dot3.addCssClass("dot");
        
        loadingDots.append(dot1);
        loadingDots.append(dot2);
        loadingDots.append(dot3);
        
        suggestionList.append(loadingDots);
        loadingDots.visible = true;
    }
    
    void hideLoadingDots()
    {
        if (loadingDots !is null)
        {
            suggestionList.remove(loadingDots);
            loadingDots = null;
        }
    }

    void appendHeader(string text)
    {
        ListBoxRow headerRow = new ListBoxRow();
        headerRow.selectable = false;
        Label headerLabel = new Label(text);
        headerLabel.addCssClass("search-results-header");
        headerLabel.halign = Align.Start;
        headerRow.setChild(headerLabel);
        suggestionList.append(headerRow);
    }

    Box buildResultRow(string cid)
    {
        Box rowBox = new Box(Orientation.Vertical, 4);
        rowBox.addCssClass("search-result-row");

        Label titleLabel = new Label("CID "~cid);
        titleLabel.addCssClass("search-result-title");
        titleLabel.halign = Align.Start;

        Label detailLabel = new Label("PubChem");
        detailLabel.addCssClass("search-result-detail");
        detailLabel.halign = Align.Start;

        rowBox.append(titleLabel);
        rowBox.append(detailLabel);
        return rowBox;
    }

    Box buildResultRow(Compound compound, bool isPrimary = false, bool isLoading = false)
    {
        Box rowBox = new Box(Orientation.Horizontal, 8);
        rowBox.addCssClass("search-result-row");
        if (!isPrimary)
            rowBox.addCssClass("similar-result");

        if (isPrimary && isLoading)
        {
            auto dotsBox = new Box(Orientation.Horizontal, 1);
            dotsBox.addCssClass("loading-dots");
            dotsBox.valign = Align.Center;
            
            auto dot1 = new Label(".");
            dot1.addCssClass("dot");
            auto dot2 = new Label(".");
            dot2.addCssClass("dot");
            auto dot3 = new Label(".");
            dot3.addCssClass("dot");
            
            dotsBox.append(dot1);
            dotsBox.append(dot2);
            dotsBox.append(dot3);
            
            rowBox.append(dotsBox);
        }
        
        auto titleBox = new Box(Orientation.Vertical, 2);
        auto titleLabel = new Label(compound.name);
        titleLabel.addCssClass("search-result-title");
        titleLabel.halign = Align.Start;
        titleBox.append(titleLabel);
        
        rowBox.append(titleBox);
        rowBox.hexpand = true;
        
        auto sourceLabel = new Label("["~compound.cid.to!string~"]");
        sourceLabel.addCssClass("search-result-detail");
        sourceLabel.halign = Align.End;
        rowBox.append(sourceLabel);
        
        auto pubchemLabel = new Label("PubChem");
        pubchemLabel.addCssClass("search-result-detail");
        pubchemLabel.halign = Align.End;
        pubchemLabel.marginStart = 8;
        rowBox.append(pubchemLabel);

        return rowBox;
    }

    void onSearchBtnClicked()
    {
        string text = searchEntry.text;
        if (text.length >= 2 && onSearch !is null)
            onSearch(text);
    }

    void onSearchActivated()
    {
        string text = searchEntry.text;
        if (text.length < 2)
        {
            suggestionList.visible = false;
            suggestionList.removeAll();
            return;
        }
        if (onSearch !is null)
            onSearch(text);
    }

    void onRowActivated(ListBoxRow row)
    {
        writeln("[Homepage] onRowActivated called");
        if (row is null)
        {
            writeln("[Homepage] Row is null");
            return;
        }

        int index = row.getIndex();
        writeln("[Homepage] Row activated, index: ", index);
        
        void* similarData = row.getData("similar-compound");
        if (similarData !is null)
        {
            auto similarCompound = cast(Compound)similarData;
            if (similarCompound !is null && onCompoundSelected !is null)
            {
                writeln("[Homepage] Similar compound selected: CID ", similarCompound.cid);
                onCompoundSelected(index, similarCompound);
                return;
            }
        }
        
        // Primary result selected (index 0)
        if (index == 0 && lastSearchCompound !is null && onCompoundSelected !is null)
        {
            writeln("[Homepage] Primary result selected");
            onCompoundSelected(index, lastSearchCompound);
        }
    }

public:
    void delegate(string query) onSearch;
    void delegate(int index, Compound compound) onCompoundSelected;

    this()
    {
        super(Orientation.Vertical, 0);
        writeln("[Homepage] Constructor started");
        
        Overlay overlay = new Overlay();
        overlay.hexpand = true;
        overlay.vexpand = true;

        Background bg = new Background();
        bg.hexpand = true;
        bg.vexpand = true;
        bg.addCssClass("homepage-background");
        overlay.setChild(bg);

        Box centering = new Box(Orientation.Vertical, 0);
        centering.hexpand = true;
        centering.vexpand = true;
        centering.halign = Align.Center;
        centering.valign = Align.Center;

        Box content = buildContent();
        centering.append(content);
        overlay.addOverlay(centering);

        append(overlay);
        writeln("[Homepage] Constructor completed");
    }

    SearchEntry getSearchEntry()
    {
        return searchEntry;
    }

    ListBox getSuggestionList()
    {
        return suggestionList;
    }

    void addSimilarResults(Compound[] similarCompounds)
    {
        writeln("[Homepage] addSimilarResults called with ", similarCompounds.length, " compounds");
        
        if (!isLoading || similarCompounds is null || similarCompounds.length == 0)
            return;
        
        // Add similar compounds
        foreach (simCompound; similarCompounds)
        {
            writeln("[Homepage] Adding similar compound: CID ", simCompound.cid);
            auto row = new ListBoxRow();
            row.setData("similar-compound", cast(void*)simCompound);
            row.setChild(buildResultRow(simCompound, false));
            suggestionList.append(row);
        }
        
        isLoading = false;
        updatePrimaryResultCompletion();
        
        writeln("[Homepage] addSimilarResults completed");
    }

    void clearResults()
    {
        searchEntry.text = "";
        suggestionList.visible = false;
        suggestionList.removeAll();
        hideLoadingDots();
    }

    void displayError(string str)
    {
        suggestionList.removeAll();

        ListBoxRow headerRow = new ListBoxRow();
        headerRow.selectable = false;
        Label headerLabel = new Label("Error");
        headerLabel.addCssClass("search-results-header");
        headerLabel.addCssClass("error-header");
        headerLabel.halign = Align.Start;
        headerRow.setChild(headerLabel);
        suggestionList.append(headerRow);

        ListBoxRow row = new ListBoxRow();
        row.selectable = false;

        Box rowBox = new Box(Orientation.Vertical, 4);
        rowBox.addCssClass("search-result-row");

        Label errorLabel = new Label(str);
        errorLabel.addCssClass("search-result-detail");
        errorLabel.addCssClass("error-text");
        errorLabel.halign = Align.Start;

        rowBox.append(errorLabel);
        row.setChild(rowBox);

        suggestionList.append(row);
        suggestionList.visible = true;
    }

    void displayResults(string query, string[] cids)
    {
        writeln("[Homepage] displayResults called, query: ", query, ", cids count: ", cids !is null ? cids.length : 0);
        suggestionList.removeAll();

        if (cids is null)
        {
            writeln("[Homepage] No results found");
            displayError("No results found for \""~query~"\"");
            return;
        }

        appendHeader("Search results for \""~query~"\"");

        foreach (cid; cids)
        {
            writeln("[Homepage] Adding row for CID: ", cid);
            ListBoxRow row = new ListBoxRow();
            row.setData("cid", cast(void*)cid);
            row.setChild(buildResultRow(cid));
            suggestionList.append(row);
        }

        suggestionList.visible = true;
        writeln("[Homepage] displayResults completed");
    }

    void displayResults(string query, Compound compound, Compound[] similarCompounds = null)
    {
        writeln("[Homepage] displayResults called, query: ", query, 
                ", compound: ", compound !is null ? compound.name : "null", 
                ", similar: ", similarCompounds !is null ? similarCompounds.length : 0);
        
        suggestionList.removeAll();
        isLoading = false;
        loadingDots = null;
        lastSearchCompound = compound;

        if (compound is null)
        {
            writeln("[Homepage] No results found");
            displayError("No results found for \""~query~"\"");
            return;
        }

        writeln("[Homepage] Adding primary result for: ", compound.name);
        auto primaryRow = new ListBoxRow();
        bool showLoading = similarCompounds is null;
        isLoading = showLoading;
        primaryRow.setChild(buildResultRow(compound, true, showLoading));
        suggestionList.append(primaryRow);
        
        if (similarCompounds !is null && similarCompounds.length > 0)
            addSimilarResults(similarCompounds);
        else if (!showLoading)
        {
            suggestionList.visible = false;
            return;
        }

        suggestionList.visible = true;
        writeln("[Homepage] displayResults completed");
    }
}
