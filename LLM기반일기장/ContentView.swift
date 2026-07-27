//
//  ContentView.swift
//  LLM기반일기장
//
//  Created by Jinoo Kang on 7/20/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var authManager = BiometricAuthManager()
    @StateObject private var diaryStore = DiaryStore()
    @StateObject private var llmService = LLMService()
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                mainAppLayout
                    .onAppear {
                        diaryStore.loadMockDataIfEmpty()
                    }
            } else {
                LoginView()
                    .environmentObject(authManager)
            }
        }
        .environmentObject(authManager)
        .environmentObject(diaryStore)
        .environmentObject(llmService)
    }
    
    @ViewBuilder
    private var mainAppLayout: some View {
        #if os(macOS)
        NavigationView {
            List {
                NavigationLink(
                    destination: HomeView(),
                    label: {
                        Label("일기장", systemImage: "book.closed.fill")
                    }
                )
                NavigationLink(
                    destination: SettingsView(),
                    label: {
                        Label("설정", systemImage: "gearshape.fill")
                    }
                )
            }
            .listStyle(.sidebar)
            .frame(minWidth: 150)
            
            // Default center/detail view on startup
            HomeView()
        }
        .frame(minWidth: 800, minHeight: 550)
        #else
        TabView {
            NavigationView {
                HomeView()
            }
            .tabItem {
                Label("일기장", systemImage: "book.closed.fill")
            }
            
            NavigationView {
                SettingsView()
            }
            .tabItem {
                Label("설정", systemImage: "gearshape.fill")
            }
        }
        #endif
    }
}

#Preview {
    ContentView()
}
