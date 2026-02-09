module wikia.pubchem.compound;

import wikia.pubchem;

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
    double xlogp;
}

class Compound
{
    static Compound[int] registry;

    static Compound getOrCreate(int cid)
    {
        assert(cid != 0, "CID must not be zero");
        if (auto p = cid in registry)
            return *p;

        auto c = new Compound(cid);
        registry[cid] = c;
        return c;
    }

    int cid;
    int[] sids;
    Properties properties;

package:
    this(int cid)
    {
        assert(cid != 0, "CID must not be zero");
        this.cid = cid;
    }

    Conformer3D _conformer3D;
    string[] _synonyms;

public:
    ref string name()
    {
        if (properties.title == null)
            properties = getProperties!"cid"(cid)[0].properties;

        return properties.title;
    }

    ref string smiles()
    {
        if (properties.smiles == null)
            properties = getProperties!"cid"(cid)[0].properties;

        return properties.smiles;
    }

    ref string iupac()
    {
        if (properties.iupac == null)
            properties = getProperties!"cid"(cid)[0].properties;

        return properties.iupac;
    }

    ref string inchi()
    {
        if (properties.inchi == null)
            properties = getProperties!"cid"(cid)[0].properties;

        return properties.inchi;
    }

    static Compound byName(string name)
    {
        return getProperties(name);
    }

    static Compound byID(string TYPE)(int id)
    {
        return getProperties!TYPE(id)[0];
    }

    string[] synonyms()
    {
        if (_synonyms.length == 0)
            _synonyms = getSynonyms!"cid"(cid)[0];

        return _synonyms;
    }

    Conformer3D conformer3D()
    {
        if (_conformer3D is null)
            _conformer3D = getConformer3D!"cid"(cid)[0];

        return _conformer3D;
    }
}