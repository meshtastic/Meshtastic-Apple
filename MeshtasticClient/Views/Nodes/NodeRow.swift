import SwiftUI

struct NodeRow: View {
    var node: NodeInfoModel
    var connected: Bool

    var body: some View {
        VStack (alignment: .leading) {
            
            HStack() {
                
                CircleText(text: node.user.shortName, color: Color.blue).offset(y: 1).padding(.trailing, 5)
                Text(node.user.longName).font(.title2)
            }
            .padding([.trailing])
            
            HStack (alignment: .bottom){
                
                Image(systemName: "timer.square").font(.headline).foregroundColor(.blue).symbolRenderingMode(.hierarchical)
                
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
