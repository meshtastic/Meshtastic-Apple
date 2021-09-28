import Foundation

class MessageData: ObservableObject {
    
    private static var documentsFolder: URL {
        do {
            return try FileManager.default.url(for: .documentDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
        } catch {
            fatalError("Can't find documents directory.")
        }
    }
    
    private static var fileURL: URL {
        return documentsFolder.appendingPathComponent("messages.data")
    }
    
    @Published var messages: [MessageModel] = []
    
    func load() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let data = try? Data(contentsOf: Self.fileURL) else {
                //#if DEBUG
                DispatchQueue.main.async {
                    self?.messages = MessageModel.data
                }
                //#endif
                return
            }
            guard let messageList = try? JSONDecoder().decode([MessageModel].self, from: data) else {
                fatalError("Can't decode saved node data.")
            }
            DispatchQueue.main.async {
                self?.messages = messageList
            }
        }
    }
    func save() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let messages = self?.messages else { fatalError("Self out of scope") }
            guard let data = try? JSONEncoder().encode(messages) else { fatalError("Error encoding data") }
            do {
                let outfile = Self.fileURL
                try data.write(to: outfile)
            } catch {
                fatalError("Can't write to file")
            }
        }
    }
}
