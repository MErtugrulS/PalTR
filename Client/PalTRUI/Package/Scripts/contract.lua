local Contract = {}
Contract.SCHEMA_VERSION = 1
Contract.DEFAULT_TAB = "CLAN"
Contract.TABS = {
    { id = "CLAN", label = "Klanım" },
    { id = "DIPLOMACY", label = "Diplomasi" },
    { id = "ALLIANCE", label = "İttifak" },
    { id = "CHAT", label = "Sohbet" }
}

function Contract.accepts(snapshot)
    return type(snapshot) == "table"
        and tonumber(snapshot.schema_version) == Contract.SCHEMA_VERSION
        and type(snapshot.player) == "table"
        and type(snapshot.guild) == "table"
        and type(snapshot.members) == "table"
        and type(snapshot.relations) == "table"
end

return Contract
