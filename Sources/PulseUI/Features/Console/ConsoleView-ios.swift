// The MIT License (MIT)
//
// Copyright (c) 2020–2023 Alexander Grebenyuk (github.com/kean).

import SwiftUI
import CoreData
import Pulse
import Combine

#if os(iOS)

public struct ConsoleView: View {
    @StateObject private var viewModel: ConsoleViewModel

    public init(store: LoggerStore = .shared) {
        self.init(viewModel: .init(store: store))
    }

    init(viewModel: ConsoleViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }


    public var body: some View {
        _ConsoleView(viewModel: viewModel)
            .sheet(isPresented: $viewModel.isShowingFilters) {
                NavigationView {
                    ConsoleSearchCriteriaView(viewModel: viewModel.searchCriteriaViewModel)
                        .inlineNavigationTitle("Filters")
                        .navigationBarItems(trailing: Button("Done") {
                            viewModel.isShowingFilters = false
                        })
                }
            }
    }
}

struct _ConsoleView: View {
    let viewModel: ConsoleViewModel

    @State private var shareItems: ShareItems?
    @State private var isShowingAsText = false
    @State private var selectedShareOutput: ShareOutput?

    var body: some View {
        _ConsoleListView(viewModel: viewModel)
            .navigationTitle(viewModel.title)
            .navigationBarItems(
                leading: viewModel.onDismiss.map {
                    Button(action: $0) { Text("Close") }
                },
                trailing: HStack {
                    if let _ = selectedShareOutput {
                        ProgressView()
                            .frame(width: 27, height: 27)
                    } else {
                        Menu(content: { shareMenu }) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .disabled(selectedShareOutput != nil)
                    }
                    ConsoleContextMenu(viewModel: viewModel, isShowingAsText: $isShowingAsText)
                }
            )
            .sheet(item: $shareItems, content: ShareView.init)
            .sheet(isPresented: $isShowingAsText) {
                NavigationView {
                    ConsoleTextView(entities: viewModel.entitiesSubject) {
                        isShowingAsText = false
                    }
                }
            }

    }

    @ViewBuilder
    private var shareMenu: some View {
        Button(action: { share(as: .plainText) }) {
            Label("Share as Text", systemImage: "square.and.arrow.up")
        }
        Button(action: { share(as: .html) }) {
            Label("Share as HTML", systemImage: "square.and.arrow.up")
        }
    }

    private func share(as output: ShareOutput) {
        selectedShareOutput = output
        viewModel.prepareForSharing(as: output) { item in
            selectedShareOutput = nil
            shareItems = item
        }
    }
}

private struct _ConsoleListView: View {
    let viewModel: ConsoleViewModel
    @ObservedObject private var searchBarViewModel: ConsoleSearchBarViewModel

    init(viewModel: ConsoleViewModel) {
        self.viewModel = viewModel
        self.searchBarViewModel = viewModel.searchBarViewModel
    }

    var body: some View {
        let list = List {
            if #available(iOS 15, *) {
                _ConsoleSearchableContentView(viewModel: viewModel)
            } else {
                _ConsoleRegularContentView(viewModel: viewModel)
                    .onAppear(perform: viewModel.onAppear)
                    .onDisappear(perform: viewModel.onDisappear)
            }
        }
        .listStyle(.plain)

        if #available(iOS 16, *) {
            list
                .environment(\.defaultMinListRowHeight, 8) // TODO: refactor
                .searchable(text: $searchBarViewModel.text, tokens: $searchBarViewModel.tokens, token: {
                    if let image = $0.systemImage {
                        Label($0.title, systemImage: image)
                    } else {
                        Text($0.title)
                    }
                })
                .onSubmit(of: .search, viewModel.searchViewModel.onSubmitSearch)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
        } else if #available(iOS 15, *) {
            list
                .searchable(text: $searchBarViewModel.text)
                .onSubmit(of: .search, viewModel.searchViewModel.onSubmitSearch)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
        } else {
            list
        }
    }
}

@available(iOS 15, *)
private struct _ConsoleSearchableContentView: View {
    let viewModel: ConsoleViewModel
    @Environment(\.isSearching) private var isSearching

    var body: some View {
        contents.onChange(of: isSearching) {
            viewModel.searchViewModel.isViewVisible = $0
        }
    }

    @ViewBuilder
    private var contents: some View {
        if isSearching {
            ConsoleSearchView(viewModel: viewModel)
        } else {
            _ConsoleRegularContentView(viewModel: viewModel)
                .onAppear(perform: viewModel.onAppear)
                .onDisappear(perform: viewModel.onDisappear)
        }
    }
}

private struct _ConsoleRegularContentView: View {
    @ObservedObject var viewModel: ConsoleViewModel

    var body: some View {
        let toolbar = ConsoleToolbarView(title: viewModel.toolbarTitle, viewModel: viewModel)
        if #available(iOS 15.0, *) {
            toolbar.listRowSeparator(.hidden, edges: .top)
        } else {
            toolbar
        }
        #warning("sort using currently selected sorting function")
        if #available(iOS 15, *) {
            let groupByStatusCode = true
            if groupByStatusCode && viewModel.mode == .network {
                let groups = Dictionary(grouping: viewModel.entities as! [NetworkTaskEntity], by: { $0.statusCode })
                ForEach(Array(groups.keys), id: \.self) {
                    let tasks = groups[$0]!.sorted(by: { $0.createdAt < $1.createdAt })
                    PlainListClearSectionHeader(title: "Status Code: \($0)")
                    ForEach(tasks, id: \.objectID) { entity in
                        ConsoleEntityCell(entity: entity)
                            .onAppear { viewModel.onAppearCell(with: entity.objectID) }
                            .onDisappear { viewModel.onDisappearCell(with: entity.objectID) }
                    }
                }
            }
        } else {
            makeForEach(viewModel: viewModel)
        }
        footerView
    }

    @ViewBuilder
    private var footerView: some View {
        if #available(iOS 15, *), viewModel.searchCriteriaViewModel.criteria.shared.dates == .session, viewModel.order == .descending {
            Button(action: { viewModel.searchCriteriaViewModel.criteria.shared.dates.startDate = nil }) {
                Text("Show Previous Sessions")
                    .font(.subheadline)
                    .foregroundColor(Color.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .listRowSeparator(.hidden, edges: .bottom)
        }
    }
}

#if DEBUG
struct ConsoleView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ConsoleView(viewModel: .init(store: .mock))
        }
    }
}
#endif

#endif

extension ConsoleView {
    /// Creates a view pre-configured to display only network requests
    public static func network(store: LoggerStore = .shared) -> ConsoleView {
        ConsoleView(viewModel: .init(store: store, mode: .network))
    }
}
