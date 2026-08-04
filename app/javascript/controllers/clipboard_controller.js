// 文字項目的複製鍵。
//
// navigator.clipboard 只在 secure context(https 或 localhost)可用,而這個站
// 常常是在 LAN 上跑純 HTTP,所以必須有 execCommand 的後備路徑。
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "button"]

  copy() {
    const text = this.sourceTarget.textContent

    if (navigator.clipboard?.writeText) {
      navigator.clipboard.writeText(text).then(
        () => this.flash("已複製"),
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

    this.flash(ok ? "已複製" : "複製失敗")
  }

  flash(message) {
    if (!this.hasButtonTarget) return

    const button = this.buttonTarget
    const original = button.textContent
    button.textContent = message
    setTimeout(() => { button.textContent = original }, 1200)
  }
}
