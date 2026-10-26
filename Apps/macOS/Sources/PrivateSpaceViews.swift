import SwiftUI

struct PrivateSpaceCover: View {
    @ObservedObject var store: MacStore
    @State private var pin = ""
    @State private var stayOn = false
    @State private var minutes = 15
    @FocusState private var focused: Bool
    var body: some View {
        ZStack {
            Color(hex:"E5EBE6")
            VStack(alignment:.leading,spacing:24) {
                RoundedRectangle(cornerRadius:AavaGeometry.fieldRadius).fill(.gray.opacity(0.25)).frame(width:240,height:32)
                ForEach(0..<5) { n in RoundedRectangle(cornerRadius:AavaGeometry.fieldRadius).fill(.gray.opacity(0.15)).frame(height:n == 1 ? 160 : 32) }
            }.padding(70).blur(radius:18).accessibilityHidden(true).allowsHitTesting(false)
            VStack(spacing:18) {
                Image(systemName:"lock.fill").font(.system(size:27,weight:.light))
                Text("Private space").font(.system(size:24,weight:.semibold))
                Text("Enter your PIN to reveal this space.").font(.system(size:13)).foregroundStyle(.secondary)
                SecureField("PIN",text:$pin).textFieldStyle(.roundedBorder).focused($focused).onSubmit(unlock).frame(width:230)
                Toggle("Stay on when switching spaces",isOn:$stayOn).font(.system(size:12))
                HStack(spacing: 4) {
                    ForEach([15, 30, 60], id: \.self) { value in
                        Button { minutes = value } label: { Text(value == 60 ? "1 hour" : "\(value) min").font(.system(size: 12)).padding(10) }.buttonStyle(AavaHoverButton(active: minutes == value))
                            .accessibilityLabel("Lock after \(value) idle minutes")
                    }
                }
                if let error=store.privateError { Text(error).font(.system(size:12)).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true) }
                Button("Unlock space",action:unlock).buttonStyle(AavaPrimaryButton()).disabled(pin.isEmpty)
                Text(stayOn ? "Idle time is measured separately for this space." : "Leaving this space locks it immediately.").font(.system(size:11)).foregroundStyle(.secondary)
            }.padding(30).frame(width:330).background(.regularMaterial,in:RoundedRectangle(cornerRadius:AavaGeometry.frameRadius)).foregroundStyle(.primary)
        }.clipShape(RoundedRectangle(cornerRadius:AavaGeometry.surfaceRadius)).onAppear { minutes=store.space.privacy?.idleMinutes ?? 15; stayOn=store.space.privacy?.stayOn ?? false; focused=true }
    }
    private func unlock() { let entered=pin; pin=""; store.unlockPrivateSpace(pin:entered,stayOn:stayOn,minutes:minutes) }
}

struct PrivateSpaceSetup: View {
    @ObservedObject var store: MacStore
    @State private var pin=""
    @State private var confirmation=""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Text("Make this space private").font(.title2.bold()); Spacer(); Button("Cancel") { store.showPrivateSetup=false }.buttonStyle(AavaHoverButton(inset: 10)) }
            Text("Choose a PIN with 6–12 digits. Aava stores a salted PIN verifier in your Mac Keychain.").font(.system(size:13)).foregroundStyle(.secondary)
            SecureField("New PIN",text:$pin).focused($focused)
            SecureField("Confirm PIN",text:$confirmation).onSubmit(save)
            Text("Locks hide the page and sidebar contents, including from accessibility tools. Private spaces lock again when Aava restarts or your Mac locks.").font(.system(size:12)).foregroundStyle(.secondary)
            Text("This locks access inside Aava. It does not encrypt Chromium’s files against someone with access to your Mac account. Pages and calls may keep running while locked; audio output is muted and popup windows close.").font(.system(size:12)).foregroundStyle(.secondary)
            if let error=store.privateError { Text(error).foregroundStyle(.red).font(.system(size:12)) }
            HStack { Spacer(); Button("Set PIN",action:save).buttonStyle(AavaPrimaryButton()).disabled(!PINVerifier.isValid(pin) || pin != confirmation) }
        }.textFieldStyle(.roundedBorder).padding(28).frame(width:450).onAppear { focused=true }
    }
    private func save() { let a=pin,b=confirmation; pin="";confirmation="";store.finishPrivateSetup(pin:a,confirmation:b) }
}

struct ArcImportPreview: View {
    @ObservedObject var store: MacStore
    let preview: ArcImportResult
    @State private var selected: Set<UUID> = []
    private var existing: Set<String> { Set(store.state.spaces.compactMap(\.arcSourceID)) }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Text("Bring your Arc spaces").font(.title2.bold()); Spacer();Button("Cancel") { store.importPreview=nil }.buttonStyle(AavaHoverButton(inset: 10)) }
            Text("Spaces, pinned tabs and nested folders. Every space gets separate cookies, sign-ins and extensions.").font(.system(size:13)).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    ForEach(preview.spaces) { space in
                        let duplicate=existing.contains(space.arcSourceID ?? "")
                        Toggle(isOn:Binding(get:{ selected.contains(space.id) },set:{ if $0 { selected.insert(space.id) } else { selected.remove(space.id) } })) {
                            VStack(alignment:.leading,spacing:3) {
                                Text("\(space.emoji)  \(space.name)")
                                Text(duplicate ? "Already imported" : "\(space.tabs.filter { $0.url != nil }.count) tabs · \(space.saved.count) saved pages and folders").font(.caption).foregroundStyle(.secondary)
                            }
                        }.disabled(duplicate)
                    }
                }.padding(3)
            }.frame(maxHeight:300)
            Text("This step brings your sidebar. Use More from Arc for bookmarks, history, an extension restore list and optional website sessions. Profile Favorites are copied into independent folders; split views become folders. Arc stays unchanged, and Aava saves a session backup before importing.").font(.system(size:12)).foregroundStyle(.secondary)
            if preview.skippedItems > 0 { Text("\(preview.skippedItems) unsupported, missing or duplicate items were skipped.").font(.caption).foregroundStyle(.secondary) }
            HStack { Spacer(); Button("Import \(selected.count) spaces") { store.commitArcImport(selected:selected) }.buttonStyle(AavaPrimaryButton()).disabled(selected.isEmpty) }
        }.frame(maxWidth:480).onAppear { selected=Set(preview.spaces.filter { !existing.contains($0.arcSourceID ?? "") }.map(\.id)) }
    }
}
