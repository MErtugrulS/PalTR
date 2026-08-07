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
end

return Contract
