import SwiftUI
import MapKit

struct LineRowView: View {
    @ObservedObject var line: LineViewModel
    @ObservedObject var lineStore: LineStore
    @ObservedObject var viewModel: NotepadViewModel
    
    #if os(iOS)
    let editorUIFont: UIFont
    #else
    let editorUIFont: NSFont
    #endif
    
    // Bindings for parent state
    var focusedLineId: FocusState<UUID?>.Binding
    @Binding var isLocationSearchActive: Bool
    @Binding var locationSearchLineId: UUID?
    @Binding var previousFocusedLineId: UUID?
    var isLocationSearchFocused: FocusState<Bool>.Binding
    @ObservedObject var locationSearchService: LocationSearchService
    
    // Mood picker bindings
    @Binding var showMoodPicker: Bool
    @Binding var moodPickerLineId: UUID?
    var onMoodSelected: (String) -> Void
    
    // Callbacks
    var onReturn: () -> Void
    var onEmptyBackspace: () -> Void
    var onTextChanged: (String, String) -> Void // oldText, newText
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                #if os(iOS)
                LineTextView(
                    text: $line.text,
                    placeholder: "Write a sentence...",
                    font: editorUIFont,
                    isFirstResponder: Binding(
                        get: { lineStore.focusedId == line.id && !isLocationSearchActive },
                        set: { isFirst in
                            if isFirst && !isLocationSearchActive {
                                focusedLineId.wrappedValue = line.id
                                lineStore.focus(line.id)
                            }
                        }
                    ),
                    lineId: line.id,
                    onReturn: onReturn,
                    onEmptyBackspace: onEmptyBackspace,
                    onTextChangedDirectly: { oldText, newText in
                        onTextChanged(oldText, newText)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                #else
                TextField("Write a sentence...", text: $line.text)
                    .font(.body)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Note: Focus handling on macOS might need adjustment if focusedLineId is not passed correctly
                    // For now, we rely on the parent managing focus via other means or this binding if it works
                    .onSubmit {
                        onReturn()
                    }
                #endif
                
                statusIndicator
                    .id("\(line.id)-\(line.status.hashValue)")
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            
            if let locationName = viewModel.getLocation(for: line.id) {
                locationView(name: locationName)
            }
            
            if isLocationSearchActive && locationSearchLineId == line.id {
                inlineLocationSearch
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            if showMoodPicker && moodPickerLineId == line.id {
                inlineMoodPicker
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    @ViewBuilder
    private var statusIndicator: some View {
        HStack(spacing: 4) {
            let results = viewModel.lineParsingResults[line.id] ?? []
            ResultViewBuilder(
                results: results,
                status: line.status,
                parseSources: { viewModel.parseSources(from: $0) }, // Assuming this method exists or accessible
                faviconURL: { viewModel.faviconURL(for: $0) } // Assuming this method exists or accessible
            )
        }
    }
    
    private func locationView(name: String) -> some View {
        HStack(spacing: 4) {
            Button {
                // Open location search to change location
                locationSearchLineId = line.id
                previousFocusedLineId = focusedLineId.wrappedValue ?? lineStore.focusedId
                focusedLineId.wrappedValue = nil
                lineStore.focusedId = nil
                withAnimation(.easeInOut(duration: 0.2)) {
                    isLocationSearchActive = true
                }
                locationSearchService.searchQuery = ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    isLocationSearchFocused.wrappedValue = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    Text(name)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button(action: {
                viewModel.removeLocation(from: line.id)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }
    
    private var inlineLocationSearch: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                
                TextField("Search location", text: $locationSearchService.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .autocorrectionDisabled()
                    .focused(isLocationSearchFocused)
                    .onTapGesture {
                        focusedLineId.wrappedValue = nil
                    }
                
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isLocationSearchActive = false
                    }
                    locationSearchService.reset()
                    isLocationSearchFocused.wrappedValue = false
                    locationSearchLineId = nil
                    if let prev = previousFocusedLineId {
                        focusedLineId.wrappedValue = prev
                        lineStore.focus(prev)
                    }
                } label: {
                    Text("Cancel")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            #if os(iOS)
            .background(Color(uiColor: .secondarySystemBackground))
            #else
            .background(Color(nsColor: .controlBackgroundColor))
            #endif
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            
            // Results
            if !locationSearchService.searchResults.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(locationSearchService.searchResults, id: \.self) { result in
                            Button {
                                viewModel.setLocation(for: line.id, locationName: result.title)
                                
                                // Remove @ character from line text if present
                                if let currentText = lineStore.linesById[line.id]?.text, currentText.contains("@") {
                                    let textWithoutAt = currentText.replacingOccurrences(of: "@", with: "")
                                    lineStore.updateText(for: line.id, newText: textWithoutAt)
                                }
                                
                                withAnimation {
                                    isLocationSearchActive = false
                                }
                                locationSearchService.reset()
                                isLocationSearchFocused.wrappedValue = false
                                locationSearchLineId = nil
                                
                                // Restore focus
                                if let prev = previousFocusedLineId {
                                    focusedLineId.wrappedValue = prev
                                    lineStore.focus(prev)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .foregroundStyle(.primary)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .frame(maxHeight: 200)
                #if os(iOS)
                .background(Color(uiColor: .systemBackground))
                #else
                .background(Color(nsColor: .windowBackgroundColor))
                #endif
                .cornerRadius(8)
                .shadow(radius: 4)
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
        }
    }
    
    private var inlineMoodPicker: some View {
        VStack(spacing: 8) {
            HStack {
                Text("How are you feeling?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showMoodPicker = false
                    }
                    moodPickerLineId = nil
                    if let prev = previousFocusedLineId {
                        focusedLineId.wrappedValue = prev
                        lineStore.focus(prev)
                    }
                } label: {
                    Text("Cancel")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack(spacing: 20) {
                ForEach(["😢", "😕", "😐", "🙂", "😊"], id: \.self) { emoji in
                    Button {
                        onMoodSelected(emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 32))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .padding(12)
        #if os(iOS)
        .background(Color(uiColor: .secondarySystemBackground))
        #else
        .background(Color(nsColor: .controlBackgroundColor))
        #endif
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}
