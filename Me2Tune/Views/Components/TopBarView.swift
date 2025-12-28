//
//  TopBarView.swift
//  Me2Tune
//
//  顶部信息栏 - 应用信息和旋转开关
//

import SwiftUI

struct TopBarView: View {
    @Binding var isRotationEnabled: Bool
    
    var body: some View {
        HStack {
            infoSection
            
            Spacer()
            
            rotationToggle
                .offset(y: -14)
                .padding(.trailing, 12)
        }
        .frame(height: 50)
    }
    
    // MARK: - Info Section
    
    private var infoSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "headphones")
                .foregroundColor(.gray)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 3) {
                Text("Me2Tune")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                Text("AAC | 264 kbps | 16 bit | 44.1 kHz | Stereo")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.08))
        )
    }
    
    // MARK: - Rotation Toggle
    
    private var rotationToggle: some View {
        Button(action: {
            isRotationEnabled.toggle()
        }) {
            Circle()
                .fill(isRotationEnabled ? Color(hex: "#00E5FF").opacity(0.8) : Color.white.opacity(0.15))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "record.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isRotationEnabled ? .black : .gray)
                )
                .shadow(color: isRotationEnabled ? Color(hex: "#00E5FF").opacity(0.6) : .clear, radius: 10)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TopBarView(isRotationEnabled: .constant(true))
        .frame(height: 170)
        .padding(.horizontal, 12)
        .background(Color.black)
}
