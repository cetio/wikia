module app;

import std.file : exists, readText;
import std.stdio : writeln;

import gio.types : ApplicationFlags;
import gtk.application;
import gtk.css_provider;
import gtk.style_context;
import gdk.display;
import gtk.types : STYLE_PROVIDER_PRIORITY_APPLICATION;

import gui.wikia : WikiaWindow;

immutable string cssPath = "resources/style.css";

class WikiaApp : Application
{
private:
    CssProvider cssProvider;

    void applyCss()
    {
        cssProvider = new CssProvider();
        if (cssPath.exists)
            cssProvider.loadFromString(cssPath.readText);
        else
            writeln("Warning: CSS file not found at "~cssPath);

        StyleContext.addProviderForDisplay(
            Display.getDefault(), cssProvider, STYLE_PROVIDER_PRIORITY_APPLICATION);
    }

    void onActivate()
    {
        applyCss();
        WikiaWindow window = new WikiaWindow(this);
        window.present();
    }

public:
    this()
    {
        super("org.wikia.pubchem", ApplicationFlags.DefaultFlags);
        connectActivate(&onActivate);
    }
}

void main(string[] args)
{
    WikiaApp app = new WikiaApp();
    app.run(args);
}
