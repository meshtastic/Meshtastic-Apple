import Foundation

class MeshData: ObservableObject {
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
        return documentsFolder.appendingPathComponent("nodeinfo.data")
    }
    
    @Published var nodes: [NodeInfoModel] = []

    func load() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let data = try? Data(contentsOf: Self.fileURL) else {
                #if DEBUG
                DispatchQueue.main.async {
                    self?.nodes = NodeInfoModel.data
                }
                #endif
                return
            }
            guard let nodeList = try? JSONDecoder().decode([NodeInfoModel].self, from: data) else {
				do {
					// If the file is borked delete it so we stop crashing
					try FileManager.default.removeItem(at: Self.fileURL)
				}
				catch {
					
					fatalError("Can't delete saved node data.")
				}
				
                fatalError("Can't decode saved node data.")
            }
            DispatchQueue.main.async {
                self?.nodes = nodeList
            }
        }
    }
    func save() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let scrums = self?.nodes else { fatalError("Self out of scope") }
            guard let data = try? JSONEncoder().encode(scrums) else { fatalError("Error encoding data") }
            do {
                let outfile = Self.fileURL
                try data.write(to: outfile)
            } catch {
                fatalError("Can't write to file")
            }
        }
    }
}
