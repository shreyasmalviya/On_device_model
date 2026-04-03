# 📖 On-Device Gemma 3 Chat Application — Complete Documentation

> A Flutter Android chat application that runs Google's **Gemma 3 270M IT (q8)** large language model entirely on your phone, with zero internet connection required.

---

## Table of Contents

1. [How Does AI Run on Your Phone?](#1-how-does-ai-run-on-your-phone)
2. [Understanding the Model File](#2-understanding-the-model-file)
3. [App Architecture](#3-app-architecture)
4. [The Native Inference Engine Pipeline](#4-the-native-inference-engine-pipeline)
5. [What Each File Does](#5-what-each-file-does)
6. [The Bugs We Fixed & Why They Happened](#6-the-bugs-we-fixed--why-they-happened)
7. [Key Concepts Glossary](#7-key-concepts-glossary)
8. [How to Modify & Extend the App](#8-how-to-modify--extend-the-app)

---

## 1. How Does AI Run on Your Phone?

### The Big Picture

When you use ChatGPT or Google Gemini online, your text is sent to massive data centers with hundreds of powerful GPUs. Those servers process your question and send back the answer.

**Our app is completely different.** The entire AI brain (the "model") lives as a single file on your phone. When you type a message, your phone's own processor (Snapdragon 865) does all the mathematical calculations to generate a response. No internet. No servers. Everything happens locally.

### How Does a Phone "Think"?

An AI model is essentially a **giant mathematical formula** with billions of numbers (called "weights" or "parameters"). When you type "Hello", the following happens:

```
Step 1: TOKENIZATION
   "Hello" → [17534]
   Your text is converted into numbers that the model understands.
   Each number represents a "token" (a word or piece of a word).

Step 2: EMBEDDING
   [17534] → [0.23, -0.67, 0.12, 0.89, ...]  (256 dimensions)
   Each token number is converted into a vector (a list of decimal numbers)
   that captures the "meaning" of that word in mathematical space.

Step 3: TRANSFORMER LAYERS (The Brain)
   The vector passes through multiple "transformer layers" — each layer
   is a massive matrix multiplication that refines the meaning.
   
   Gemma 3 270M has 18 transformer layers, each performing:
   - Self-Attention: "Which other words should I pay attention to?"
   - Feed-Forward: "Based on context, what should I predict next?"
   
   Each layer multiplies your vector by matrices with millions of numbers.

Step 4: SAMPLING (Choosing the Next Word)
   After all layers, the model outputs probabilities for ALL possible 
   next words (256,000+ options in Gemma's vocabulary):
   
   "Hi"     → 15.2% probability
   "Hello"  → 12.8% probability
   "Hey"    → 8.3% probability
   "I"      → 5.1% probability
   ...
   
   The model randomly picks one based on these probabilities.
   This is controlled by "temperature" (higher = more random).

Step 5: REPEAT
   The chosen word is added to the sequence, and Steps 2-4 repeat
   to generate the NEXT word. This continues until the model generates
   a special <eos> (End of Sequence) token, meaning "I'm done talking."
```

### Why 270M Parameters?

"270M" means the model has **270 million** mathematical weights. Each weight is a decimal number like `0.3847264`. To fit 270M of these on a phone:

- **Full precision (FP32)**: Each number uses 32 bits = 4 bytes → 270M × 4 = **1.08 GB**
- **8-bit quantized (Q8)**: Each number compressed to 8 bits = 1 byte → 270M × 1 = **~270 MB**

Your model file (`gemma3-270m-it-q8.task`) uses **8-bit quantization (q8)**, which is why it's about 270 MB instead of 1 GB.

---

## 2. Understanding the Model File

### What is a `.task` File?

A `.task` file is Google's **MediaPipe Task Bundle** format. It's a single packaged file containing:

```
gemma3-270m-it-q8.task
├── Model Weights (the 270M numbers, quantized to 8-bit)
├── Tokenizer (dictionary mapping words ↔ numbers)
├── Model Configuration (layer count, hidden size, etc.)
├── Chat Template (how to format <start_of_turn>user\n...\n<end_of_turn>)
└── Metadata (model name, version, supported features)
```

### Breaking Down the Filename

```
gemma3  -  270m  -  it    -  q8     .task
  │         │       │        │        │
  │         │       │        │        └── File format (MediaPipe Task Bundle)
  │         │       │        └── Quantization: 8-bit integers
  │         │       └── "Instruction Tuned" (trained to follow instructions/chat)
  │         └── 270 Million parameters
  └── Google Gemma 3 model family
```

### What is "Instruction Tuned" (IT)?

There are two types of language models:
- **Base models**: Just predict the next word. If you say "The capital of France is", it completes: "Paris"
- **Instruction Tuned (IT)**: Specially trained to follow instructions and have conversations. If you say "What is the capital of France?", it responds: "The capital of France is Paris."

Your model is IT, which is why it can chat naturally.

---

## 3. App Architecture

### High-Level Overview

```
┌─────────────────────────────────────────────────────┐
│                    Flutter App (Dart)                │
│                                                      │
│  ┌──────────────┐     ┌───────────────────────────┐ │
│  │  chat_screen  │────▶│      llm_service           │ │
│  │  (UI Layer)   │     │  (Business Logic Layer)    │ │
│  │              │◀────│                             │ │
│  │  • Messages   │     │  • Model Loading            │ │
│  │  • Text Input │     │  • Chat Session Management  │ │
│  │  • Status Bar │     │  • Response Generation      │ │
│  └──────────────┘     └───────────┬───────────────┘ │
│                                    │                  │
│                          ┌─────────▼─────────┐       │
│                          │   flutter_gemma    │       │
│                          │  (Plugin - Dart)   │       │
│                          │                    │       │
│                          │  • InferenceModel  │       │
│                          │  • InferenceChat   │       │
│                          │  • Message Format  │       │
│                          └─────────┬─────────┘       │
└────────────────────────────────────┼─────────────────┘
                                     │ Platform Channel
                                     │ (Dart ↔ Kotlin)
┌────────────────────────────────────┼─────────────────┐
│               Android Native (Kotlin/C++)            │
│                                     │                 │
│                          ┌─────────▼─────────┐       │
│                          │  EngineFactory     │       │
│                          │  (Routes to engine)│       │
│                          └─────────┬─────────┘       │
│                                    │                  │
│                   ┌────────────────▼───────────────┐ │
│                   │     LiteRT-LM Engine           │ │
│                   │   (com.google.ai.edge.litertlm)│ │
│                   │                                 │ │
│                   │  • Engine (model loading)       │ │
│                   │  • Conversation (chat state)    │ │
│                   │  • SamplerConfig (topK/temp)    │ │
│                   └────────────────┬───────────────┘ │
│                                    │                  │
│                          ┌─────────▼─────────┐       │
│                          │  C++ Runtime       │       │
│                          │  (liblitertlm.so)  │       │
│                          │                    │       │
│                          │  • TFLite Backend  │       │
│                          │  • XNNPack (CPU)   │       │
│                          │  • OpenCL (GPU)    │       │
│                          └────────────────────┘       │
└──────────────────────────────────────────────────────┘
```

### The Flow of a Single Message

When you type "Hello" and press Send:

```
1. chat_screen.dart → _handleSubmitted("Hello")
       │
2. llm_service.dart → generateResponse("Hello")
       │
3. InferenceChat → addQueryChunk(Message.text("Hello"))
       │
4. transformToChatPrompt() → "Hello"
   (For .task files, raw text is sent because the engine handles templates)
       │
5. Platform Channel → Kotlin addQueryChunk("Hello")
       │
6. LiteRtLmSession → conversation.sendMessageAsync(Contents.of([Content.Text("Hello")]))
       │
7. C++ Engine → Tokenize → Run through 18 transformer layers → Sample next token
       │                                                              │
       │                    ┌──────────────────────────────────────────┘
       │                    │ (repeats for each word until <eos>)
       │                    ▼
8. MessageCallback.onMessage("Hi") → onMessage("!") → onMessage(" How") → ... → onDone()
       │
9. Accumulated response: "Hi! How can I help you today?"
       │
10. chat_screen.dart → Display in chat bubble
```

---

## 4. The Native Inference Engine Pipeline

### Two Engines Inside flutter_gemma

The `flutter_gemma` plugin contains TWO completely different AI engines:

| Engine | Files Supported | Technology | Status |
|--------|----------------|------------|--------|
| **MediaPipe Engine** | `.bin`, `.tflite` | Old Google MediaPipe SDK | Works, but has JNI bugs with `.task` Gemma 3 |
| **LiteRT-LM Engine** | `.litertlm`, `.task` (patched) | New Google LiteRT-LM SDK | ✅ What we use (same as Google AI Edge Gallery) |

### How EngineFactory Routes Your Model

```kotlin
// In EngineFactory.kt (PATCHED by us)
fun createFromModelPath(modelPath: String): InferenceEngine {
    return when {
        ".litertlm" → LiteRtLmEngine   // Modern engine
        ".task"     → LiteRtLmEngine   // PATCHED! Was MediaPipeEngine before
        ".bin"      → MediaPipeEngine   // Legacy engine
        ".tflite"   → MediaPipeEngine   // Legacy engine
    }
}
```

**Before our patch:** `.task` → MediaPipeEngine → Empty responses  
**After our patch:** `.task` → LiteRtLmEngine → Working responses ✅

### CPU vs GPU Backend

The LiteRT-LM engine can run on either your phone's CPU or GPU:

| Backend | How It Works | Our Experience |
|---------|-------------|----------------|
| **CPU** | Uses ARM NEON instructions via XNNPack | ✅ Works correctly |
| **GPU** | Uses OpenCL for parallel computation | ❌ NaN decode errors on Snapdragon 865 |

We use **CPU** because your Snapdragon 865's GPU OpenCL driver has a compatibility issue with 8-bit quantized Gemma 3 matrix operations.

---

## 5. What Each File Does

### Your Project Files

#### `lib/main.dart`
The entry point. Creates the `LlmService` and passes it to `ChatScreen`.

#### `lib/services/llm_service.dart`
**The brain of the app.** Manages the entire model lifecycle:

```dart
// State Machine
LlmStatus.unloaded → loading → loaded → (error)
                                  ↓
                              unloaded (offload)
```

Key methods:
- `loadModel(filePath)` — Installs the model file, creates the engine, opens a chat session
- `generateResponse(prompt)` — Sends text to the model and returns the AI's response
- `offloadModel()` — Frees memory by closing the model

#### `lib/screens/chat_screen.dart`
**The UI layer.** Handles:
- File picker dialog (choosing the `.task` file)
- Copying the model to secure app storage (bypasses Android file restrictions)
- Displaying messages in chat bubbles
- Loading/error status indicators

#### `android/app/proguard-rules.pro`
Tells the Android build system: "Don't delete these classes when optimizing!"
Without this, the release build would strip out MediaPipe/Protobuf classes → crash.

### Plugin Files (flutter_gemma)

#### `EngineFactory.kt` (PATCHED)
Decides which native engine to use based on file extension. We patched it to route `.task` files to the modern LiteRT-LM engine.

#### `LiteRtLmEngine.kt`
Wraps Google's `com.google.ai.edge.litertlm.Engine` class. Handles:
- Model file loading and validation
- Backend selection (CPU/GPU/NPU)
- Cache directory for faster reload (~1-2s vs ~10s cold start)

#### `LiteRtLmSession.kt`
Wraps `Conversation` from the LiteRT-LM SDK. Handles:
- Adding user messages
- Generating responses (sync and async)
- Token streaming (word by word)

---

## 6. The Bugs We Fixed & Why They Happened

### Bug 1: R8 Build Failure
**Symptom:** `Missing class com.google.mediapipe.proto.CalculatorProfileProto`  
**Cause:** Android's code optimizer (R8) was stripping MediaPipe classes it thought were unused  
**Fix:** Added `proguard-rules.pro` with `-keep class com.google.mediapipe.** { *; }`

### Bug 2: Empty Responses (MediaPipe Engine)
**Symptom:** Model loads correctly, prompt sent correctly, but response is always `""`  
**Root Cause:** The MediaPipe engine's native C++ code has a JNI threading bug. When it tries to call back to Java/Kotlin from a background thread, it encounters `GetEnv: not attached` — the thread isn't registered with the Java VM. The callback silently fails, and the engine immediately signals "done" with an empty string.  
**Fix:** Switched from MediaPipe engine to LiteRT-LM engine by patching `EngineFactory.kt`

### Bug 3: App Crash on GPU Backend
**Symptom:** `Fatal signal 6 (SIGABRT)` immediately when loading model  
**Root Cause:** When we tried `.litertlm` file extension trick, the LiteRT-LM engine tried to parse the file with its own binary format parser. The `.task` format has a different "magic number" (first few bytes that identify the file type). The engine saw the wrong magic number and called `abort()`.  
**Fix:** Reverted the file extension trick. The LiteRT-LM engine actually supports `.task` files natively — it just needs to receive them with the correct `.task` extension.

### Bug 4: `<pad><pad><pad>...` Response (GPU Decode Error)
**Symptom:** Model generates hundreds of `<pad>` tokens  
**Root Cause:** The GPU backend (OpenCL) on Snapdragon 865 produces `NaN` (Not-a-Number) values during the decode/sampling step. The engine detects this: `Invalid decode and sample result. The sampled token is casted to 0 to avoid crash.` Token 0 in Gemma's vocabulary = `<pad>`.  
**Fix:** Switched to CPU backend (`PreferredBackend.cpu`). The CPU path uses XNNPack which correctly handles 8-bit quantized operations on ARM NEON.

### Bug 5: Stale Cached Model File
**Symptom:** App tries to load `gemma3-270m-it-q8.litertlm` even after code was reverted  
**Root Cause:** The `UnifiedModelManager` inside `flutter_gemma` cached the model path in SharedPreferences. Even after changing the code, the old `.litertlm` path persisted.  
**Fix:** Added cleanup code in `chat_screen.dart` to delete stale `.litertlm` files, and instructed user to clear app data.

---

## 7. Key Concepts Glossary

### Quantization
Compressing model weights from high precision (32-bit float) to lower precision (8-bit integer) to reduce file size and memory usage. 
- **FP32**: Full precision, 4 bytes per weight
- **Q8 (INT8)**: 8-bit, 1 byte per weight (what we use)
- **Q4 (INT4)**: 4-bit, 0.5 bytes per weight (smallest, least accurate)

### Tokenizer
A dictionary that converts text to numbers and back:
- "Hello" → `[17534]` (encoding)
- `[17534]` → "Hello" (decoding)
- Special tokens: `<eos>` (end), `<pad>` (padding), `<start_of_turn>` (chat markers)

### Transformer Architecture
The core AI architecture. Each "layer" has:
- **Self-Attention**: Determines which words in the input are most relevant to each other
- **Feed-Forward Network**: Processes the attention output through learned weights
- Gemma 3 270M has **18** of these layers stacked on top of each other

### KV Cache (Key-Value Cache)
When generating word-by-word, the model stores intermediate calculations from previous words. This avoids recalculating everything from scratch for each new word. `maxTokens: 1024` means the cache can hold up to 1024 words of context.

### Temperature
Controls randomness of word selection:
- **0.0**: Always picks the most likely word (deterministic, boring)
- **1.0**: Standard randomness (what we use, matches Google Gallery)
- **2.0**: Very random (creative but potentially nonsensical)

### Top-K Sampling
Only consider the top K most likely next words. `topK: 64` means: from 256,000+ possible words, only consider the 64 most probable ones, then randomly pick from those.

### Top-P (Nucleus) Sampling
Instead of a fixed count, consider words that together make up P% of probability. `topP: 0.95` means: keep adding the most probable words until their combined probability reaches 95%, then pick from that set.

### Platform Channel
Flutter's mechanism for Dart code to call native (Kotlin/Swift) code:
```
Dart (your app) ←→ Platform Channel ←→ Kotlin (native engine)
```
It's like a bridge between the UI world and the hardware world.

### JNI (Java Native Interface)
How Kotlin/Java code calls C++ code (and vice versa). The AI model runs in C++, but Flutter talks to Kotlin, so the chain is:
```
Dart → Kotlin → JNI → C++ (actual model execution)
```

### XNNPack
Google's optimized CPU inference library. It uses ARM NEON instructions (special hardware-accelerated math operations) to run neural networks fast on mobile CPUs.

### OpenCL
A standard for running general computations on GPUs. When we say "GPU backend", the model runs on your phone's Adreno 650 GPU using OpenCL.

---

## 8. How to Modify & Extend the App

### Change Model Parameters

Edit `lib/services/llm_service.dart`:

```dart
// More creative responses
_chat = await _model?.createChat(
   topK: 100,        // Consider more words (more diverse)
   temperature: 1.5,  // More random/creative
   topP: 0.98,       // Wider probability window
);

// More focused/precise responses
_chat = await _model?.createChat(
   topK: 10,          // Only top 10 words
   temperature: 0.3,   // Very deterministic
   topP: 0.5,         // Narrow window
);
```

### Use a Different Model

You can use any `.task` model file from HuggingFace. Just download it and select it in the app. Examples:
- `Gemma3-1B-IT` (1 billion params, larger, smarter, slower)
- `Qwen2.5-1.5B-Instruct` (different model family)

### Add Streaming Responses (Word by Word)

The `llm_service.dart` already has `generateResponseStream()`. To use it in the UI, modify `chat_screen.dart`:

```dart
// Instead of:
final response = await widget.llmService.generateResponse(text);

// Use:
final stream = widget.llmService.generateResponseStream(text);
await for (final token in stream!) {
  setState(() {
    _messages.last = ChatMessage(
      text: _messages.last.text + token,
      isUser: false,
    );
  });
}
```

### Switch to GPU (if you get a compatible phone)

```dart
_model = await FlutterGemma.getActiveModel(
  maxTokens: 1024,
  preferredBackend: PreferredBackend.gpu, // Try GPU
);
```

GPU is faster but not all phones support it correctly (as we learned!).

---

## Summary of Final Configuration

| Setting | Value | Why |
|---------|-------|-----|
| Engine | LiteRT-LM | Same as Google AI Edge Gallery, no JNI bugs |
| Backend | CPU | GPU produces NaN on Snapdragon 865 q8 models |
| Max Tokens | 1024 | Google Gallery default, good balance of context vs memory |
| Top-K | 64 | Google Gallery default |
| Temperature | 1.0 | Google Gallery default |
| Top-P | 0.95 | Google Gallery default |
| Model Type | gemmaIt | Instruction-tuned Gemma format |

---

*Documentation created on April 2, 2026*  
*Model: Gemma 3 270M IT Q8 running on Samsung Galaxy S20 FE (Snapdragon 865)*
