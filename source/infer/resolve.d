module infer.resolve;

import std.regex : ctRegex, matchAll;
import infer.config;

private:

// INN/pharmaceutical suffixes (4+ chars to avoid false positives)
immutable string[] DRUG_SUFFIXES = [
    "amine", "azine", "azole", "caine", "cillin",
    "cline", "done", "idine", "mycin", "olol",
    "ophen", "orphan", "oxin", "pine", "pril",
    "profen", "ridol", "sartan", "setron", "statin",
    "tadine", "terol", "thiazide", "tidine", "tinib",
    "tine", "triptan", "xaban", "zepam", "zodone",
    "zole", "zosin", "barb", "dryl", "mab", "nib",
    "vir", "pam", "lam", "fil",
];

bool hasDrugSuffix(string lower)
{
    foreach (suf; DRUG_SUFFIXES)
        if (lower.length > suf.length && lower[$ - suf.length .. $] == suf)
            return true;
    return false;
}

public:

string[] extractCompoundNames(string text)
{
    if (text.length < 20)
        return [];

    auto cfg = config();
    if (!cfg.autoResolveRabbitHoles)
        return [];

    string trunc = text.length > 2000 ? text[0 .. 2000] : text;
    bool[string] names;

    // Suffix-matched drug names (e.g. ketamine, phencyclidine, midazolam)
    enum wordRe = ctRegex!(`[A-Za-z][A-Za-z0-9]*(?:-[A-Za-z0-9]+)*`);
    foreach (m; matchAll(trunc, wordRe))
    {
        if (m.hit.hasDrugSuffix)
            names[m.hit] = true;
    }

    // Chemical formulas (C17H21NO)
    enum formulaRe = ctRegex!(`[A-Z][a-z]?\d+(?:[A-Z][a-z]?\d*)+`);
    foreach (m; matchAll(trunc, formulaRe))
        names[m.hit] = true;

    // IUPAC-style names (contain parentheses + hyphens in chemical context)
    enum iupacRe = ctRegex!(`\d+(?:,\d+)*-\([A-Za-z,]+\)-[A-Za-z][A-Za-z0-9-]*`);
    foreach (m; matchAll(trunc, iupacRe))
        names[m.hit] = true;

    // InChI strings
    enum inchiRe = ctRegex!(`InChI=[^\s]+`);
    foreach (m; matchAll(trunc, inchiRe))
        names[m.hit] = true;

    // Number-prefixed compounds (2C-B, 5-MeO-DMT, 4-AcO-DMT)
    enum numCompoundRe = ctRegex!(`\d+[A-Za-z0-9,-]*-[A-Z][A-Za-z0-9-]*`);
    foreach (m; matchAll(trunc, numCompoundRe))
        names[m.hit] = true;

    return names.keys;
}
