import { Controller } from "@hotwired/stimulus"
import { post } from "@rails/request.js"
import { nextFrame } from "helpers/timing_helpers"

export default class extends Controller {
  static targets = [ "item", "container" ]
  static values = { url: String }
  static classes = [ "draggedItem", "hoverContainer" ]

  connect() {
    this.audioFiles = [
      "/audio/B3.mp3",
      "/audio/C3.mp3",
      "/audio/D4.mp3",
      "/audio/E3.mp3",
      "/audio/Fsharp4.mp3",
      "/audio/G3.mp3"
    ]

    this.preloadedAudioFiles = this.audioFiles.map(file => {
      const audio = new Audio(file)
      audio.load()
      return audio
    });
  }

  dragEnter(event) {
    event.preventDefault()
    const container = this.#containerContaining(event.target)

    if (!container) { return }

    if (container !== this.sourceContainer) {
      this.#playZither()
    }
  }

  #containerContaining(element) {
    return this.containerTargets.find(container => container.contains(element) || container === element)
  }

  #playZither() {
    const randomIndex = Math.floor(Math.random() * this.preloadedAudioFiles.length)
    const audio = this.preloadedAudioFiles[randomIndex]
    const audioInstance = new Audio(audio.src)
    audioInstance.play()
  }
}
