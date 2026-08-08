local ChatState = {}
ChatState.__index = ChatState

function ChatState.new()
    return setmetatable({
        available = false,
        messages = {}
    }, ChatState)
end

function ChatState:set_available(available)
    self.available = available == true
end

function ChatState:replace(messages)
    if type(messages) ~= "table" then return false end
    self.messages = messages
    return true
end

function ChatState:append(message)
    if type(message) ~= "table" then return false end
    table.insert(self.messages, message)
    return true
end

function ChatState:clear()
    self.messages = {}
end

return ChatState
