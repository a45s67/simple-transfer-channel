// Copy button for text items.
//
// navigator.clipboard is only available in a secure context (https or
// localhost), and this app often runs over plain HTTP on a LAN, so the
// execCommand fallback is not optional.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "button"]

  copy() {
    const text = this.sourceTarget.textContent

    if (navigator.clipboard?.writeText) {
      navigator.clipboard.writeText(text).then(
        () => this.flash("Copied"),
        () => this.fallback(text)
      )
    } else {
      this.fallback(text)
    }
  }

  fallback(text) {
    const area = document.createElement("textarea")
    area.value = text
    area.setAttribute("readonly", "")
    area.style.position = "fixed"
    area.style.opacity = "0"
    document.body.appendChild(area)
    area.select()

    let ok = false
    try {
      ok = document.execCommand("copy")
    } catch {
      ok = false
    }
    document.body.removeChild(area)

    this.flash(ok ? "Copied" : "Copy failed")
  }

  flash(message) {
    if (!this.hasButtonTarget) return

    const button = this.buttonTarget
    const original = button.textContent
    button.textContent = message
    setTimeout(() => { button.textContent = original }, 1200)
  }
}
