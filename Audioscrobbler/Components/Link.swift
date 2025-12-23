//
//  Link.swift
//  Audioscrobbler
//
//  Created by Victor Gama on 25/11/2022.
//

import SwiftUI

struct Link<Label: View>: View {
    var destination: URL
    var label: Label

    init(_ text: any StringProtocol, destination: URL) where Label == Text {
        self.destination = destination
        self.label = Text(text)
    }

    init(destination: URL, @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.label = label()
    }

    var body: some View {
        Button {
            NSWorkspace.shared.open(self.destination)
        } label: {
            label
        }
        .buttonStyle(.link)
    }
}

struct Link_Previews: PreviewProvider {
    static var previews: some View {
        Link("Hello", destination: URL(string: "https://vito.io")!)
    }
}
