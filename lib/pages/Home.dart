import 'dart:io';
import 'dart:typed_data';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CURIBOT THE CHATBOT',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Gemini gemini = Gemini.instance;
  final FlutterTts flutterTts = FlutterTts(); // Initialize TTS
  List<ChatMessage> messages = [];
  List<List<ChatMessage>> chatHistory = [];
  ChatUser currentUser = ChatUser(id: "0", firstName: "User");
  ChatUser geminiUser = ChatUser(id: "1", firstName: "Curibot");

  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _loadChatHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text("Curibot"),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _startNewSession,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
          ),
        ],
      ),
      body: _selectedIndex == 0 ? _buildChatUI() : _buildHistoryUI(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }

  Widget _buildChatUI() {
    return DashChat(
      inputOptions: InputOptions(trailing: [
        IconButton(
          onPressed: _sendMediaMessage,
          icon: const Icon(Icons.camera),
        ),
      ]),
      currentUser: currentUser,
      onSend: _sendMessage,
      messages: messages,
    );
  }

  Widget _buildHistoryUI() {
    return ListView.builder(
      itemCount: chatHistory.length,
      itemBuilder: (context, index) {
        return ListTile(
          title: Text('Chat Session ${index + 1}'),
          subtitle: Text(chatHistory[index].last.text),
          onTap: () {
            setState(() {
              messages = chatHistory[index];
              _selectedIndex = 0;
            });
          },
          trailing: IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => _deleteChatSession(index),
          ),
        );
      },
    );
  }

  void _sendMessage(ChatMessage chatMessage) {
    setState(() {
      chatMessage.text = _sanitizeText(chatMessage.text);
      messages = [chatMessage, ...messages];
    });
    _saveMessages();

    // Speak the user's message immediately
    _speak(chatMessage.text);

    String question = chatMessage.text;
    List<Uint8List>? images;
    if (chatMessage.medias?.isNotEmpty ?? false) {
      images = [
        File(chatMessage.medias!.first.url).readAsBytesSync(),
      ];
    }
    gemini.streamGenerateContent(question, images: images).listen((event) {
      ChatMessage? lastMessage = messages.firstOrNull;
      String response = event.content?.parts?.fold(
          "", (previous, current) => "$previous ${current.text}") ??
          "";

      if (lastMessage != null && lastMessage.user == geminiUser) {
        lastMessage = messages.removeAt(0);
        lastMessage.text += response;
        setState(() {
          messages = [lastMessage!, ...messages];
        });
      } else {
        ChatMessage message = ChatMessage(
          user: geminiUser,
          createdAt: DateTime.now(),
          text: response,
        );
        setState(() {
          messages = [message, ...messages];
        });
      }

      // Wait 5 seconds after the response is displayed and then speak it
      Future.delayed(Duration(seconds: 0), () async {
        await _speak(response);  // Speak the response after the delay
      });

      _saveMessages();
    });
  }

  void _sendMediaMessage() async {
    final prefs = await SharedPreferences.getInstance();
    String customText = prefs.getString('custom_text') ?? "Get the text in the picture?";

    ImagePicker picker = ImagePicker();
    XFile? file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      ChatMessage chatMessage = ChatMessage(
        user: currentUser,
        createdAt: DateTime.now(),
        text: customText,
        medias: [
          ChatMedia(
            url: file.path,
            fileName: "",
            type: MediaType.image,
          )
        ],
      );
      _sendMessage(chatMessage);
    }
  }

  Future<void> _speak(String text) async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5); // Adjust speech rate
    await flutterTts.speak(text);
  }

  Future<void> _saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> messageList = messages.map((msg) => jsonEncode(msg.toJson())).toList();
    prefs.setStringList('chat_messages', messageList);
  }

  Future<void> _loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? messageList = prefs.getStringList('chat_messages');
    if (messageList != null) {
      setState(() {
        messages = messageList.map((msg) => ChatMessage.fromJson(jsonDecode(msg))).toList();
      });
    }
  }

  Future<void> _loadChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? historyList = prefs.getStringList('chat_history');
    if (historyList != null) {
      setState(() {
        chatHistory = historyList
            .map((history) => List<ChatMessage>.from(
            jsonDecode(history).map((msg) => ChatMessage.fromJson(msg))))
            .toList();
      });
    }
  }

  void _onNavItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _startNewSession() {
    if (messages.isNotEmpty) {
      chatHistory.add(List.from(messages));
    }
    setState(() {
      messages = [];
      _selectedIndex = 0;
    });
    _saveChatHistory();
  }

  Future<void> _saveChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> updatedHistory = chatHistory
        .map((history) => jsonEncode(history.map((msg) => msg.toJson()).toList()))
        .toList();
    prefs.setStringList('chat_history', updatedHistory);
  }

  Future<void> _deleteChatSession(int index) async {
    setState(() {
      chatHistory.removeAt(index);
    });
    final prefs = await SharedPreferences.getInstance();
    List<String> updatedHistory = chatHistory
        .map((history) => jsonEncode(history.map((msg) => msg.toJson()).toList()))
        .toList();
    prefs.setStringList('chat_history', updatedHistory);
  }

  String _sanitizeText(String text) {
    return text.replaceAll(RegExp(r'\*+'), ''); // Remove asterisks
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  TextEditingController _controller = TextEditingController();
  String customText = "";

  @override
  void initState() {
    super.initState();
    _loadCustomText();
  }

  Future<void> _loadCustomText() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      customText = prefs.getString('custom_text') ?? "Get the text in the picture?";
      _controller.text = customText;
    });
  }

  Future<void> _saveCustomText() async {
    final prefs = await SharedPreferences.getInstance();
    String sanitizedText = _sanitizeText(_controller.text);
    prefs.setString('custom_text', sanitizedText);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Custom Text',
                hintText: 'Enter a custom message',
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saveCustomText,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  String _sanitizeText(String text) {
    return text.replaceAll(RegExp(r'\*+'), ''); // Remove asterisks
  }
}
