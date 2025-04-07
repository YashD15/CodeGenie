import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

//Set API key below before building
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeManager.initialize();
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class ThemeManager {
  static late SharedPreferences _prefs;
  static bool _isDarkMode = true;
  static final _controller = StreamController<bool>.broadcast();

  static Stream<bool> get themeStream => _controller.stream;
  static bool get isDarkMode => _isDarkMode;

  static Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _isDarkMode = _prefs.getBool('dark_mode') ?? true;
  }

  static void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    _prefs.setBool('dark_mode', _isDarkMode);
    _controller.add(_isDarkMode);
  }
}

class ConversationMemory {
  final List<Content> _history = [];
  final int _maxHistoryLength = 15;
  CodeMemory codeMemory = CodeMemory();

  void addUserMessage(String message) {
    if (_history.length >= _maxHistoryLength * 2) {
      _history.removeRange(0, 2);
    }
    _history.add(Content.text('User: $message'));
  }

  void addModelResponse(String response) {
    if (_history.length >= _maxHistoryLength * 2) {
      _history.removeRange(0, 2);
    }
    _history.add(Content.text('Assistant: $response'));

    // Extract and store code blocks
    codeMemory.extractAndStoreCode(response);
  }

  List<Content> getHistoryForPrompt() {
    return _history.toList();
  }

  String getContextSummary() {
    return _history
        .map((content) {
          if (content.parts.isNotEmpty && content.parts.first is TextPart) {
            return (content.parts.first as TextPart).text;
          }
          return '';
        })
        .join('\n');
  }

  void clear() {
    _history.clear();
    codeMemory.clear();
  }

  Map<String, dynamic> toJson() {
    return {
      'history':
          _history.map((content) {
            if (content.parts.isNotEmpty && content.parts.first is TextPart) {
              return {'text': (content.parts.first as TextPart).text};
            }
            return {'text': ''};
          }).toList(),
      'codeMemory': codeMemory.toJson(),
    };
  }

  void fromJson(Map<String, dynamic> json) {
    _history.clear();

    final history = json['history'] as List<dynamic>;
    for (var item in history) {
      _history.add(Content.text(item['text'] as String));
    }

    if (json.containsKey('codeMemory')) {
      codeMemory.fromJson(json['codeMemory']);
    }
  }
}

class CodeMemory {
  final Map<String, CodeSnippet> _codeSnippets = {};
  int _counter = 0;

  void extractAndStoreCode(String text) {
    final regex = RegExp(r'```(\w*)\n([\s\S]*?)```');
    final matches = regex.allMatches(text);

    for (final match in matches) {
      final language = match.group(1)?.trim() ?? 'text';
      final code = match.group(2)?.trim() ?? '';

      if (code.isNotEmpty) {
        final snippetId = 'snippet_${_counter++}';
        _codeSnippets[snippetId] = CodeSnippet(
          id: snippetId,
          language: language,
          code: code,
          createdAt: DateTime.now(),
        );
      }
    }
  }

  List<CodeSnippet> getAllSnippets() {
    final snippets = _codeSnippets.values.toList();
    snippets.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return snippets;
  }

  CodeSnippet? getLatestSnippet() {
    final snippets = getAllSnippets();
    return snippets.isNotEmpty ? snippets.first : null;
  }

  CodeSnippet? getSnippetById(String id) {
    return _codeSnippets[id];
  }

  void updateSnippet(String id, String newCode) {
    if (_codeSnippets.containsKey(id)) {
      final oldSnippet = _codeSnippets[id]!;
      _codeSnippets[id] = CodeSnippet(
        id: id,
        language: oldSnippet.language,
        code: newCode,
        createdAt: oldSnippet.createdAt,
        updatedAt: DateTime.now(),
      );
    }
  }

  void clear() {
    _codeSnippets.clear();
    _counter = 0;
  }

  Map<String, dynamic> toJson() {
    return {
      'counter': _counter,
      'snippets': _codeSnippets.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
    };
  }

  void fromJson(Map<String, dynamic> json) {
    _counter = json['counter'] ?? 0;
    _codeSnippets.clear();

    final snippets = json['snippets'] as Map<String, dynamic>?;
    if (snippets != null) {
      snippets.forEach((key, value) {
        _codeSnippets[key] = CodeSnippet.fromJson(value);
      });
    }
  }
}

class CodeSnippet {
  final String id;
  final String language;
  final String code;
  final DateTime createdAt;
  final DateTime? updatedAt;

  CodeSnippet({
    required this.id,
    required this.language,
    required this.code,
    required this.createdAt,
    this.updatedAt,
  });

  String get formattedCode => '```$language\n$code\n```';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'language': language,
      'code': code,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory CodeSnippet.fromJson(Map<String, dynamic> json) {
    return CodeSnippet(
      id: json['id'],
      language: json['language'],
      code: json['code'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt:
          json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isDarkMode = ThemeManager.isDarkMode;

  @override
  void initState() {
    super.initState();
    ThemeManager.themeStream.listen((isDark) {
      setState(() {
        _isDarkMode = isDark;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CodeGenie',
      debugShowCheckedModeBanner: false,
      theme: _isDarkMode ? _buildDarkTheme() : _buildLightTheme(),
      home: const ChatScreen(),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: const Color(0xFF00FF9D),
        secondary: const Color(0xFF00B4FF),
        surface: const Color(0xFF1A1A1A),
        onSurface: Colors.white,
      ),
      useMaterial3: true,
      cardTheme: CardTheme(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF2A2A2A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF3A3A3A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00FF9D), width: 2),
        ),
      ),
      scaffoldBackgroundColor: const Color(0xFF121212),
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: const Color(0xFF007A5A),
        secondary: const Color(0xFF0076A3),
        surface: Colors.white,
        onSurface: Colors.black,
      ),
      useMaterial3: true,
      cardTheme: CardTheme(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF007A5A), width: 2),
        ),
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class BottomInsetAvoidingWidget extends StatelessWidget {
  final Widget child;

  const BottomInsetAvoidingWidget({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: child,
    );
  }
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  late final GenerativeModel _model;
  String? _editingMessageId;
  String? _apiKey;
  bool _isInitialized = false;
  late AnimationController _typingAnimationController;
  late AnimationController _loadingAnimationController;
  final ConversationMemory _conversationMemory = ConversationMemory();
  String? _codeToModify;

  final List<String> _suggestedPrompts = [
    "Python code to read a csv file and print the data",
    "Flutter code to create a simple calculator",
    "Python code to implement flask app",
    "React code to create a login form",
    "Java code for palindrome checker",
  ];

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _loadApiKey();
    _loadConversationMemory();
    _typingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _loadingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _typingAnimationController.dispose();
    _loadingAnimationController.dispose();
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    // Try to load from .env file first
    String apiKey = dotenv.env['Gemini'] ?? '';
    // If not found in .env, try to load from SharedPreferences
    if (apiKey.isEmpty) {
      final apiKey = prefs.getString('gemini_api_key') ?? '';
    }

    setState(() {
      //Add your own gemini api key here statically or during using app
      //Also you can create .env and variable as 'Gemini'
      _apiKey = apiKey.isNotEmpty ? apiKey : 'YOUR_API_KEY';
      _initializeModel();
    });
  }

  void _initializeModel() {
    try {
      print(
        'Initializing model with API key: ${_apiKey?.substring(0, 5)}...',
      ); // Debug log
      _model = GenerativeModel(
        model:
            'gemini-2.0-flash', // Changed from gemini-2.0-flash to gemini-pro
        apiKey: _apiKey!,
        generationConfig: GenerationConfig(
          temperature: 0.7,
          topK: 40,
          topP: 0.95,
          maxOutputTokens: 2048,
        ),
      );
      setState(() {
        _isInitialized = true;
      });
      print('Model initialized successfully'); // Debug log
    } catch (e) {
      print('Error initializing model: $e'); // Debug log
      setState(() {
        _isInitialized = false;
      });
    }
  }

  Future<void> _saveApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', apiKey);
    setState(() {
      _apiKey = apiKey;
      _initializeModel();
    });
  }

  Future<void> _loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final messagesJson = prefs.getString('chat_messages');

    if (messagesJson != null) {
      final List<dynamic> decodedMessages = json.decode(messagesJson);
      setState(() {
        _messages =
            decodedMessages.map((msg) => ChatMessage.fromJson(msg)).toList();
      });
    }
  }

  Future<void> _saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final messagesJson = json.encode(
      _messages.map((msg) => msg.toJson()).toList(),
    );
    await prefs.setString('chat_messages', messagesJson);
  }

  Future<void> _loadConversationMemory() async {
    final prefs = await SharedPreferences.getInstance();
    final memoryJson = prefs.getString('conversation_memory');

    if (memoryJson != null) {
      final decodedMemory = json.decode(memoryJson);
      _conversationMemory.fromJson(decodedMemory);
    }
  }

  Future<void> _saveConversationMemory() async {
    final prefs = await SharedPreferences.getInstance();
    final memoryJson = json.encode(_conversationMemory.toJson());
    await prefs.setString('conversation_memory', memoryJson);
  }

  void _clearMessages() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear All Messages'),
            content: const Text(
              'Are you sure you want to clear all messages and conversation memory? This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _messages = [];
                    _conversationMemory.clear();
                  });
                  _saveMessages();
                  _saveConversationMemory();
                  Navigator.pop(context);
                },
                child: const Text('Clear'),
              ),
            ],
          ),
    );
  }

  Future<void> _showApiKeyDialog() async {
    final apiKeyController = TextEditingController(text: _apiKey);

    return showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('🗝️ API Key'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Enter your Gemini API key:'),
                const SizedBox(height: 10),
                TextField(
                  controller: apiKeyController,
                  decoration: const InputDecoration(
                    hintText: 'API Key',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  if (apiKeyController.text.isNotEmpty) {
                    _saveApiKey(apiKeyController.text);
                  }
                  Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          ),
    );
  }

  Future<void> _showCodeMemoryDialog() async {
    final snippets = _conversationMemory.codeMemory.getAllSnippets();
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    if (snippets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No code snippets in memory yet'),
          duration: const Duration(seconds: 2),
          backgroundColor: primaryColor,
        ),
      );
      return;
    }

    return showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.code, color: primaryColor),
                const SizedBox(width: 4),
                const Text(
                  'Stored Code Snippets',
                  style: TextStyle(fontSize: 18),
                ),
              ],
            ),
            titlePadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            backgroundColor:
                isDarkMode ? const Color(0xFF1A1A1A) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            content: Container(
              width: double.maxFinite,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: snippets.length,
                itemBuilder: (context, index) {
                  final snippet = snippets[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    color: isDarkMode ? const Color(0xFF2A2A2A) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color:
                            isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
                        width: 1,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: primaryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  snippet.language,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: primaryColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _formatTimestamp(snippet.createdAt),
                                style: TextStyle(
                                  fontSize: 10,
                                  color:
                                      isDarkMode
                                          ? Colors.grey[400]
                                          : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.copy,
                                  size: 16,
                                  color: primaryColor,
                                ),
                                onPressed:
                                    () => _copyToClipboard(
                                      snippet.code,
                                      isPlainCode: true,
                                    ),
                                tooltip: 'Copy code',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 18,
                                  minHeight: 20,
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.edit,
                                  size: 16,
                                  color: primaryColor,
                                ),
                                onPressed: () {
                                  _codeToModify = snippet.id;
                                  _promptController.text =
                                      'Modify this code: ${snippet.formattedCode}';
                                  Navigator.pop(context);
                                },
                                tooltip: 'Modify code',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 18,
                                  minHeight: 20,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      subtitle: Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color:
                              isDarkMode
                                  ? const Color(0xFF1A1A1A)
                                  : Colors.grey[100],
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color:
                                isDarkMode
                                    ? Colors.grey[800]!
                                    : Colors.grey[300]!,
                          ),
                        ),
                        child: Text(
                          snippet.code.length > 100
                              ? '${snippet.code.substring(0, 100)}...'
                              : snippet.code,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color:
                                isDarkMode
                                    ? Colors.grey[300]
                                    : Colors.grey[800],
                          ),
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _showCodeDetailDialog(snippet);
                      },
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                ),
                child: Text('Close', style: TextStyle(color: primaryColor)),
              ),
            ],
          ),
    );
  }

  Future<void> _showCodeDetailDialog(CodeSnippet snippet) async {
    return showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('${snippet.language} Snippet'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Created: ${_formatTimestamp(snippet.createdAt)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (snippet.updatedAt != null)
                      Text(
                        'Updated: ${_formatTimestamp(snippet.updatedAt!)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Code:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF1A1A1A)
                            : Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.5),
                    ),
                  ),
                  width: double.maxFinite,
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    snippet.code,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _copyToClipboard(snippet.code, isPlainCode: true);
                  Navigator.pop(context);
                },
                child: const Text('Copy Code'),
              ),
              TextButton(
                onPressed: () {
                  _codeToModify = snippet.id;
                  _promptController.text = 'Modify this code to: ';
                  Navigator.pop(context);
                },
                child: const Text('Modify'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  Future<void> _copyToClipboard(
    String text, {
    bool isWholeMessage = false,
    bool isPlainCode = false,
  }) async {
    if (isPlainCode) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Code copied to clipboard'),
            duration: const Duration(seconds: 2),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
      return;
    }

    if (isWholeMessage) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Message copied to clipboard'),
            duration: const Duration(seconds: 2),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
      return;
    }

    // Extract code from markdown format
    final codeMatch = RegExp(r'```[\s\S]*?```').firstMatch(text);
    if (codeMatch != null) {
      final code =
          codeMatch
              .group(0)!
              .replaceAll(RegExp(r'```\w*\n'), '')
              .replaceAll('```', '')
              .trim();
      await Clipboard.setData(ClipboardData(text: code));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Code copied to clipboard'),
            duration: const Duration(seconds: 2),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } else {
      // If no code block, copy the whole message
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Message copied to clipboard'),
            duration: const Duration(seconds: 2),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    }
  }

  void _editMessage(String messageId) {
    setState(() {
      _editingMessageId = messageId;
      final message = _messages.firstWhere((m) => m.id == messageId);
      _promptController.text = message.text;
    });
  }

  void _deleteMessage(String messageId) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Message'),
            content: const Text(
              'Are you sure you want to delete this message?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _messages.removeWhere((m) => m.id == messageId);
                  });
                  _saveMessages();
                  Navigator.pop(context);
                },
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }

  Future<void> _regenerateResponse(String promptText) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Add to conversation memory
      _conversationMemory.addUserMessage(promptText);

      // Prepare prompt with memory context
      final memoryContext = _conversationMemory.getContextSummary();
      final prompt = '''
You are a code generator with memory of our conversation.
Provide ONLY the code in markdown format with appropriate language tags.
Do not include any explanations or text outside of code blocks.

Context from previous messages:
$memoryContext

User request: $promptText
''';

      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      final responseText = response.text ?? 'No response generated';

      // Add to conversation memory
      _conversationMemory.addModelResponse(responseText);

      setState(() {
        _messages.add(
          ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text: responseText,
            isUser: false,
          ),
        );
        _isLoading = false;
      });

      _saveMessages();
      _saveConversationMemory();

      // Scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    } catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text: 'Error: $e',
            isUser: false,
          ),
        );
        _isLoading = false;
      });
      _saveMessages();
    }
  }

  Future<void> _sendMessage() async {
    if (_promptController.text.trim().isEmpty) return;

    final userMessage = _promptController.text;
    final messageId = DateTime.now().millisecondsSinceEpoch.toString();

    // Play typing animation
    _typingAnimationController.forward().then((_) {
      _typingAnimationController.reset();
    });

    setState(() {
      if (_editingMessageId != null) {
        final index = _messages.indexWhere((m) => m.id == _editingMessageId);
        if (index != -1) {
          _messages[index] = ChatMessage(
            id: _editingMessageId!,
            text: userMessage,
            isUser: true,
          );
        }
      } else {
        _messages.add(
          ChatMessage(id: messageId, text: userMessage, isUser: true),
        );
      }
      _isLoading = true;
    });

    _promptController.clear();
    _editingMessageId = null;

    // Add to conversation memory
    _conversationMemory.addUserMessage(userMessage);

    // Save messages immediately after adding user message
    _saveMessages();

    try {
      // Verify model initialization
      if (!_isInitialized) {
        throw Exception('Model not initialized. Please check your API key.');
      }

      // Prepare prompt with memory context
      final basePrompt = '''
You are a code generator with memory of our conversation.
Provide ONLY the code in markdown format with appropriate language tags.
Do not include any explanations or text outside of code blocks.
Example format:
```python
def hello():
    print("Hello World")
```
''';

      String prompt;

      // Check if this is a modification request for a stored code snippet
      if (_codeToModify != null) {
        final snippet = _conversationMemory.codeMemory.getSnippetById(
          _codeToModify!,
        );
        if (snippet != null) {
          prompt = '''
$basePrompt

I have this code:
```${snippet.language}
${snippet.code}
```

User request: $userMessage
''';
        } else {
          prompt = '''
$basePrompt

User request: $userMessage
''';
        }
        _codeToModify = null;
      } else {
        // Add conversation context
        final memoryContext = _conversationMemory.getContextSummary();
        prompt = '''
$basePrompt

Context from previous messages:
$memoryContext

User request: $userMessage
''';
      }

      // Print prompt for debugging
      print('Sending prompt to model: $prompt');

      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);

      if (response.text == null) {
        throw Exception('No response generated from the model');
      }

      final responseText = response.text!;

      // Add to conversation memory
      _conversationMemory.addModelResponse(responseText);

      setState(() {
        _messages.add(
          ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text: responseText,
            isUser: false,
          ),
        );
        _isLoading = false;
      });

      // Save messages and memory after receiving response
      _saveMessages();
      _saveConversationMemory();
    } catch (e) {
      print('Error in _sendMessage: $e'); // Debug log
      setState(() {
        _messages.add(
          ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text:
                'Error: Please check your API key and make sure it has access to the Gemini API. Error details: $e',
            isUser: false,
          ),
        );
        _isLoading = false;
      });
      _saveMessages();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Icon(Icons.code, color: primaryColor),
            const SizedBox(width: 6),
            const Text('CodeGenie'),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.memory),
            onPressed: _showCodeMemoryDialog,
            tooltip: 'Code Memory',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40),
          ),
          IconButton(
            icon: Icon(isDarkMode ? Icons.light_mode : Icons.dark_mode),
            onPressed: ThemeManager.toggleTheme,
            tooltip: isDarkMode ? 'Light Mode' : 'Dark Mode',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40),
          ),
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40),
            itemBuilder:
                (context) => [
                  const PopupMenuItem(
                    value: 'api_key',
                    child: Row(
                      children: [
                        Icon(Icons.key),
                        SizedBox(width: 8),
                        Text('API Key'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'clear',
                    child: Row(
                      children: [
                        Icon(Icons.delete),
                        SizedBox(width: 8),
                        Text('Clear Chat'),
                      ],
                    ),
                  ),
                ],
            onSelected: (value) {
              if (value == 'api_key') {
                _showApiKeyDialog();
              } else if (value == 'clear') {
                _clearMessages();
              }
            },
          ),
        ],
      ),
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: SafeArea(
                  bottom: false,
                  child:
                      _messages.isEmpty
                          ? _buildWelcomeScreen()
                          : _buildChatList(),
                ),
              ),
              if (_isLoading)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SpinKitWave(
                    color: primaryColor,
                    size: 30,
                    controller: _loadingAnimationController,
                  ),
                ),
              SafeArea(
                top: false,
                child: BottomInsetAvoidingWidget(
                  child: Container(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          spreadRadius: 1,
                          blurRadius: 8,
                          offset: const Offset(0, -1),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _promptController,
                            decoration: InputDecoration(
                              hintText:
                                  _editingMessageId != null
                                      ? 'Edit your message...'
                                      : 'Ask for code help...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              prefixIcon: Icon(Icons.code, color: primaryColor),
                              suffixIcon:
                                  _promptController.text.isNotEmpty
                                      ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          setState(() {
                                            _editingMessageId = null;
                                            _promptController.clear();
                                          });
                                        },
                                      )
                                      : null,
                            ),
                            maxLines: null,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendMessage(),
                            onChanged: (value) {
                              setState(() {});
                            },
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          child: IconButton(
                            onPressed: _sendMessage,
                            icon: const Icon(Icons.send),
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeScreen() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return SingleChildScrollView(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            Image.asset('assets/img/logo3.png', width: 80, height: 80),
            const SizedBox(height: 2),
            Text(
              'CodeGenie',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Your AI coding assistant',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              width: MediaQuery.of(context).size.width * 0.8,
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Examples:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final prompt in _suggestedPrompts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6.0),
                        child: InkWell(
                          onTap: () {
                            _promptController.text = prompt;
                            setState(() {});
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color:
                                  isDarkMode ? Colors.grey[900] : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color:
                                    isDarkMode
                                        ? Colors.grey[700]!
                                        : Colors.grey[300]!,
                              ),
                            ),
                            child: Text(prompt),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(
              height: 20,
            ), // Add padding at the bottom for keyboard
          ],
        ),
      ),
    );
  }

  Widget _buildChatList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(14),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final timeAgo = _getTimeAgo(message.timestamp);

        return Align(
          alignment:
              message.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color:
                  message.isUser
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                      : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    message.isUser
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                        : Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF3A3A3A)
                        : Colors.grey[300]!,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      message.isUser
                          ? Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.2)
                          : Colors.black.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 6,
                ),
              ],
            ),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Message header with timestamp and actions
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 0,
                    ),
                    color:
                        message.isUser
                            ? Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.2)
                            : Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF2A2A2A)
                            : Colors.grey[200],
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          message.isUser ? 'You' : 'CodeGenie',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              timeAgo,
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.7),
                              ),
                            ),
                            if (!message.isUser)
                              IconButton(
                                icon: const Icon(Icons.copy, size: 18),
                                onPressed: () => _copyToClipboard(message.text),
                                tooltip: 'Copy code',
                                color: Theme.of(context).colorScheme.primary,
                                constraints: const BoxConstraints(
                                  minWidth: 20,
                                  minHeight: 20,
                                ),
                                padding: EdgeInsets.zero,
                              ),
                            if (message.isUser)
                              PopupMenuButton(
                                icon: const Icon(Icons.more_horiz, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 20,
                                  minHeight: 20,
                                ),
                                itemBuilder:
                                    (context) => [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit, size: 16),
                                            SizedBox(width: 8),
                                            Text('Edit'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'copy',
                                        child: Row(
                                          children: [
                                            Icon(Icons.copy, size: 16),
                                            SizedBox(width: 8),
                                            Text('Copy'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete, size: 16),
                                            SizedBox(width: 8),
                                            Text('Delete'),
                                          ],
                                        ),
                                      ),
                                    ],
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _editMessage(message.id);
                                  } else if (value == 'copy') {
                                    _copyToClipboard(
                                      message.text,
                                      isWholeMessage: true,
                                    );
                                  } else if (value == 'delete') {
                                    _deleteMessage(message.id);
                                  }
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Message content
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: MarkdownBody(
                      data: message.text,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        code: TextStyle(
                          backgroundColor:
                              Theme.of(context).brightness == Brightness.dark
                                  ? const Color(0xFF1A1A1A)
                                  : Colors.grey[200],
                          fontFamily: 'monospace',
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color:
                              Theme.of(context).brightness == Brightness.dark
                                  ? const Color(0xFF1A1A1A)
                                  : Colors.grey[200],
                          borderRadius: const BorderRadius.all(
                            Radius.circular(8),
                          ),
                          border: Border.fromBorderSide(
                            BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withOpacity(0.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Message footer with actions
                  if (!message.isUser &&
                      index > 0 &&
                      _messages[index - 1].isUser)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 0,
                      ),
                      color:
                          Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF2A2A2A)
                              : Colors.grey[200],
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text(
                              'Regenerate',
                              style: TextStyle(fontSize: 12),
                            ),
                            onPressed:
                                () => _regenerateResponse(
                                  _messages[index - 1].text,
                                ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _getTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}

class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final List<String> codeBlocks;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    DateTime? timestamp,
    List<String>? codeBlocks,
  }) : timestamp = timestamp ?? DateTime.now(),
       codeBlocks = codeBlocks ?? _extractCodeBlocks(text);

  static List<String> _extractCodeBlocks(String text) {
    final regex = RegExp(r'```[\s\S]*?```');
    final matches = regex.allMatches(text);
    return matches.map((match) => match.group(0)!).toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'isUser': isUser,
      'timestamp': timestamp.toIso8601String(),
      'codeBlocks': codeBlocks,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'],
      text: json['text'],
      isUser: json['isUser'],
      timestamp: DateTime.parse(json['timestamp']),
      codeBlocks: List<String>.from(json['codeBlocks'] ?? []),
    );
  }
}
