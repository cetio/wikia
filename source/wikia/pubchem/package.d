module wikia.pubchem;

public import wikia.pubchem.compound;
public import wikia.pubchem.conformer3d;
import wikia.pubchem.internal;

import std.algorithm : map;
import std.array : array;
import std.conv : to;
import std.string : join;

Compound[] getProperties(string TYPE)(int[] ids...)
    if (TYPE == "cid" || TYPE == "sid")
{
    return internalGetProperties!TYPE(ids.map!(x => x.to!string).array.join(","));
}

Compound getProperties(string name)
{
    return internalGetProperties!"name"(name)[0];
}

Compound[] getID(string TYPE)(int[] ids...)
    if (TYPE == "cid" || TYPE == "sid")
{
    return internalGetID!TYPE(ids.map!(x => x.to!string).array.join(","));
}

Compound getID(string name)
{
    return internalGetID!"name"(name)[0];
}

Conformer3D[] getConformer3D(string TYPE)(int[] ids...)
    if (TYPE == "cid" || TYPE == "sid")
{
    return internalGetConformer3D!TYPE(ids.map!(x => x.to!string).array.join(","));
}

Conformer3D getConformer3D(string name)
{
    return internalGetConformer3D!("name")(name)[0];
}

// string[] getSynonyms(string KIND)(string[] ids...)
//     if (KIND == "cid" || KIND == "sid" || KIND == "name")
// {
//     orchestrator.rateLimit();
//     orchestrator.client.get(
//         orchestrator.buildURL("/compound/"~KIND~"/"~ids.join(",")~"/synonyms/JSON"), 
//         (ubyte[] data) {
//             JSONValue json = parseJSON(data.assumeUTF);
//             if ("InformationList" in json && "Information" in json["InformationList"])
//             {
//                 JSONValue info = json["InformationList"]["Information"];
//                 if (info.array.length > 0 && "Synonym" in info.array[0])
//                 {
//                     foreach (JSONValue syn; info.array[0]["Synonym"].array)
//                         compound.synonyms ~= syn.str;
//                 }
//             }
//         }, 
//         null
//     );
// }