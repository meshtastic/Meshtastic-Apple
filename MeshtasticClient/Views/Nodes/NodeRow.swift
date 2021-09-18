import SwiftUI

struct NodeRow: View {
    var node: NodeInfoModel
    var index: Int

    var body: some View {
        VStack (alignment: .leading) {
            HStack() {
                
                CircleText(text: node.user.shortName, color: Color.blue).offset(y: 1).padding(.trailing, 5)
                Text(node.user.longName).font(.title)
            }.padding(.bottom, 2)
            HStack (alignment: .top){
                
                Image(systemName: "clock").font(.subheadline).foregroundColor(.blue)
                let lastHeard = Date(timeIntervalSince1970: node.lastHeard)
                Text("Last Heard:").font(.subheadline).foregroundColor(.gray)
                Text(lastHeard, style: .relative).font(.subheadline).foregroundColor(.gray)
            }
        }.padding([.leading, .top, .bottom])
    }
}

struct NodeRow_Previews: PreviewProvider {
    static var nodes = ModelData().nodes

    static var previews: some View {
        Group {
            NodeRow(node: nodes[0], index: 0)
        }
        .previewLayout(.fixed(width: 300, height: 70))
    }
}
