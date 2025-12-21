#if os(iOS)
import SwiftUI
import UIKit

/// Single-line-ish UITextView wrapper to catch return/backspace on iOS while still allowing pasted multi-line input
struct LineTextView: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var font: UIFont
    @Binding var isFirstResponder: Bool
    var lineId: UUID
    var onReturn: () -> Void
    var onEmptyBackspace: () -> Void
    var onTextChangedDirectly: ((String, String) -> Void)? = nil
    
    func makeUIView(context: Context) -> UITextView {
        let textView = FocusableTextView()
        textView.delegate = context.coordinator
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        // Ensure layout manager allows growing
        textView.layoutManager.allowsNonContiguousLayout = false
        textView.font = font
        textView.returnKeyType = .default
        textView.keyboardType = .default
        textView.autocorrectionType = .yes
        textView.autocapitalizationType = .none
        
        let placeholderLabel = UILabel()
        placeholderLabel.text = placeholder
        placeholderLabel.font = font
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.tag = placeholderTag
        textView.addSubview(placeholderLabel)
        
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 2)
        ])
        
        // Force initial layout
        textView.setNeedsLayout()
        textView.layoutIfNeeded()
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        // Safety check: ensure view is attached or about to be
        // However, updateUIView is called before didMoveToWindow sometimes.
        
        if uiView.font != font {
            uiView.font = font
        }
        
        if uiView.text != text {
            if text.isEmpty || !uiView.isFirstResponder || !isFirstResponder {
                context.coordinator.updateTextIfNeeded(uiView, newText: text)
            }
        }

        if let focusable = uiView as? FocusableTextView {
            focusable.shouldBecomeFirstResponder = isFirstResponder
        }
        
        // Handle focus changes safely
        if isFirstResponder && !uiView.isFirstResponder {
            DispatchQueue.main.async {
                if uiView.window != nil {
                    uiView.becomeFirstResponder()
                }
            }
        } else if !isFirstResponder && uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.resignFirstResponder()
            }
        }
        
        // Invalidate intrinsic content size to ensure height is correct
        DispatchQueue.main.async {
            uiView.invalidateIntrinsicContentSize()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    fileprivate func updatePlaceholder(in textView: UITextView) {
        if let placeholderLabel = textView.viewWithTag(placeholderTag) as? UILabel {
            placeholderLabel.isHidden = !(textView.text ?? "").isEmpty
        }
    }
    
    final class Coordinator: NSObject, UITextViewDelegate {
        private var parent: LineTextView
        private var isUpdatingFromBinding = false
        
        init(_ parent: LineTextView) {
            self.parent = parent
        }
        
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            if replacement == "\n" {
                parent.onReturn()
                return false
            }
            
            let current = textView.text ?? ""
            if replacement.isEmpty, current.isEmpty {
                parent.onEmptyBackspace()
                return false
            }
            
            if replacement == "@" {
                let newText = (current as NSString).replacingCharacters(in: range, with: replacement)
                parent.onTextChangedDirectly?(current, newText)
                return false
            }
            
            if replacement == ":" {
                let newText = (current as NSString).replacingCharacters(in: range, with: replacement)
                // Only intercept if it's the start of the line (triggering the picker)
                if newText == ":" {
                    parent.onTextChangedDirectly?(current, newText)
                    return false
                }
                return true
            }
            
            return true
        }
        
        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdatingFromBinding else { return }
            
            let newText = textView.text ?? ""
            let oldText = parent.text
            // Call callback first with old and new text
            parent.onTextChangedDirectly?(oldText, newText)
            // Then update binding to keep it in sync
            if parent.text != newText {
                parent.text = newText
            }
            parent.isFirstResponder = textView.isFirstResponder
            parent.updatePlaceholder(in: textView)
            
            DispatchQueue.main.async {
                textView.invalidateIntrinsicContentSize()
            }
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFirstResponder = true
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFirstResponder = false
            let newText = textView.text ?? ""
            if parent.text != newText {
                DispatchQueue.main.async {
                    self.parent.text = newText
                }
            }
        }
        
        func updateTextIfNeeded(_ textView: UITextView, newText: String) {
            guard textView.text != newText else { return }
            isUpdatingFromBinding = true
            textView.text = newText
            isUpdatingFromBinding = false
            parent.updatePlaceholder(in: textView)
        }
    }
}

private let placeholderTag = 9_001
#endif

#if os(iOS)
private final class FocusableTextView: UITextView {
    var shouldBecomeFirstResponder: Bool = false

    override var intrinsicContentSize: CGSize {
        let size = sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: max(size.height, font?.lineHeight ?? 20))
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if shouldBecomeFirstResponder, window != nil, !isFirstResponder {
            DispatchQueue.main.async { [weak self] in
                self?.becomeFirstResponder()
            }
        }
    }
}
#endif
