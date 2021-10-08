import SwiftUI

struct NodeRow: View {
    var node: NodeInfoModel
    var connected: Bool

    var body: some View {
        VStack (alignment: .leading) {
            
            HStack() {
                
                CircleText(text: node.user.shortName, color: Color.blue).offset(y: 1).padding(.trailing, 5)
                    .offset(x: -15)
                
                if UIDevice.current.userInterfaceIdiom == .pad {
                    Text(node.user.longName).font(.headline)
                        .offset(x: -15)
                }
                else {
                    Text(node.user.longName).font(.title)
                        .offset(x: -15)
                }
            }
            .padding(.bottom, 10)
            
            HStack (alignment: .bottom){
                
                Image(systemName: "clock.badge.checkmark.fill").font(.headline).foregroundColor(.blue).symbolRenderingMode(.hierarchical)

            
                if UIDevice.current.userInterfaceIdiom == .pad {
                    
                    if connected {
                        Text("Currently Connected").font(.caption).foregroundColor(Color.accentColor)
                    }
                    else if node.lastHeard > 0 {
                        let lastHeard = Date(timeIntervalSince1970: TimeInterval(node.lastHeard))
                        Text("Last Heard: \(lastHeard, style: .relative) ago").font(.caption).foregroundColor(.gray)
                    }
                    else {
                        Text("Last Heard: Unknown").font(.caption).foregroundColor(.gray)
                    }
                    
                } else {
                    if connected {
                        Text("Currently Connected").font(.subheadline).foregroundColor(Color.accentColor)
                    }
                    else if node.lastHeard > 0 {
                        let lastHeard = Date(timeIntervalSince1970: TimeInterval(node.lastHeard))
                        Text("Last Heard: \(lastHeard, style: .relative) ago").font(.subheadline).foregroundColor(.gray)
                    }
                    else {
                        Text("Last Heard: Unknown").font(.subheadline).foregroundColor(.gray)
                    }
                }
            }
        }.padding([.leading, .top, .bottom])
    }
}

struct NodeRow_Previews: PreviewProvider {
    static var nodes = MeshData().nodes

    static var previews: some View {
        Group {
            NodeRow(node: nodes[0], connected: true)
        }
        .previewLayout(.fixed(width: 300, height: 70))
    }
}
