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

  // Actions

  async dragStart(event) {
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.dropEffect = "move"
    event.dataTransfer.setData("37ui/move", event.target)

    await nextFrame()
    this.dragItem = this.#itemContaining(event.target)
    this.sourceContainer = this.#containerContaining(this.dragItem)
    this.dragItem.classList.add(this.draggedItemClass)
  }

  dragOver(event) {
    event.preventDefault()
    const container = this.#containerContaining(event.target)
    this.#clearContainerHoverClasses()

    if (!container) { return }

    if (container !== this.sourceContainer) {
      container.classList.add(this.hoverContainerClass)
    }
  }

  dragEnter(event) {
    event.preventDefault()
    const container = this.#containerContaining(event.target)
    this.#clearContainerHoverClasses()

    if (!container) { return }

    if (container !== this.sourceContainer) {
      this.#playZither()
    }
  }

  async drop(event) {
    const container = this.#containerContaining(event.target)

    if (!container || container === this.sourceContainer) { return }

    this.wasDropped = true

    await this.#submitDropRequest(this.dragItem, container)
  }

  dragEnd() {
    this.dragItem.classList.remove(this.draggedItemClass)
    this.#clearContainerHoverClasses()

    if (this.wasDropped) {
      this.dragItem.remove()
    }

    this.sourceContainer = null
    this.dragItem = null
    this.wasDropped = false
  }

  #itemContaining(element) {
    return this.itemTargets.find(item => item.contains(element) || item === element)
  }

  #containerContaining(element) {
    return this.containerTargets.find(container => container.contains(element) || container === element)
  }

  #clearContainerHoverClasses() {
    this.containerTargets.forEach(container => container.classList.remove(this.hoverContainerClass))
  }

  #playZither() {
    const randomIndex = Math.floor(Math.random() * this.preloadedAudioFiles.length)
    const audio = this.preloadedAudioFiles[randomIndex]
    const audioInstance = new Audio(audio.src)
    audioInstance.play()
  }

  // Private

  async #submitDropRequest(item, container) {
    const body = new FormData()
    const id = item.dataset.id
    const containerTarget = container.dataset.dropTarget
    const stageId = container.dataset.stageId

    body.append("dropped_item_id", id)
    body.append("drop_target", containerTarget)
    if (stageId) {
      body.append("stage_id", stageId)
    }
    return post(this.urlValue, { body, headers: { Accept: "text/vnd.turbo-stream.html" } })
  }
}
