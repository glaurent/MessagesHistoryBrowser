//
//  ImportProgressView.swift
//  MessagesHistoryBrowser
//
//  Import progress overlay
//

import SwiftUI

// Wrapper to make Progress observable
class ObservableProgress: ObservableObject {
    @Published var fractionCompleted: Double = 0.0
    @Published var localizedDescription: String = ""
    @Published var localizedAdditionalDescription: String = ""
    
    private let progress: Progress
    private var observation: NSKeyValueObservation?
    
    init(progress: Progress) {
        self.progress = progress
        self.fractionCompleted = progress.fractionCompleted
        self.localizedDescription = progress.localizedDescription ?? ""
        self.localizedAdditionalDescription = progress.localizedAdditionalDescription ?? ""
        
        observation = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.fractionCompleted = progress.fractionCompleted
                self?.localizedDescription = progress.localizedDescription ?? ""
                self?.localizedAdditionalDescription = progress.localizedAdditionalDescription ?? ""
            }
        }
    }
}


struct ImportProgressView: View {
    @ObservedObject var progressWrapper: ObservableProgress
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView(value: progressWrapper.fractionCompleted) {
                    Text(progressWrapper.localizedDescription.isEmpty ? "Importing..." : progressWrapper.localizedDescription)
                        .font(.headline)
                } currentValueLabel: {
                    if !progressWrapper.localizedAdditionalDescription.isEmpty {
                        Text(progressWrapper.localizedAdditionalDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .progressViewStyle(.linear)
                .frame(width: 300)
                
                Text("\(Int(progressWrapper.fractionCompleted * 100))%")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.background)
                    .shadow(radius: 10)
            )
        }
    }
}
