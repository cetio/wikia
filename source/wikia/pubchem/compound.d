module wikia.pubchem.compound;

import wikia.pubchem;

// struct Dosage
// {
//     string route;
//     string threshold;
//     string light;
//     string common;
//     string strong;
//     string heavy;
// }

struct Properties
{
    string title;
    string smiles;
    string iupac;
    string inchi;

    string formula;
    double weight;
    double mass;
    int charge;
    double tpsa;
}

class Compound
{
    int cid;
    int[] sids;
    Properties properties;

    string name() => properties.title;
    string smiles() => properties.smiles;
    string iupac() => properties.iupac;
    string inchi() => properties.inchi;

    Conformer3D _conformer3D;

    package this()
    {

    }

    static Compound byName(string name)
    {
        return getProperties(name);
    }

    static Compound byID(string TYPE)(int id)
    {
        return getProperties!TYPE(id)[0];
    }

    Conformer3D conformer3D()
    {
        if (_conformer3D is null)
            _conformer3D = getConformer3D(name);

        return _conformer3D;
    }

    // ref Dosage[] dosage()
    // {
    //     if (_dosage == null)
    //     {
    //         if (pages.filter!((x) => x.source == "psychonaut").empty)
    //             pages ~= new Page(title, "psychonaut");

    //         if ("dosage" in pages.filter!((x) => x.source == "psychonaut")[0].metadata.fields)
    //         {
    //             JSONValue dosage = parseJSON(pages.filter!((x) => x.source == "psychonaut")[0].metadata.fields["dosage"]);
    //             foreach (JSONValue json; dosage.array)
    //             {
    //                 _dosage ~= Dosage(
    //                     json["route"].str,
    //                     "threshold" in json ? json["threshold"].str : null,
    //                     "light" in json ? json["light"].str : null,
    //                     "common" in json ? json["common"].str : null,
    //                     "strong" in json ? json["strong"].str : null,
    //                     "heavy" in json ? json["heavy"].str : null
    //                 );
    //             }
    //         }
    //     }

    //     return _dosage;
    // }
}