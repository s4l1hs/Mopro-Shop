import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';

/// How many questions are fetched per page (matches the backend default).
const int kQuestionsPageSize = 10;

/// Sort orders offered by the questions list endpoint. [api] is the wire value.
enum QuestionSort {
  newest('newest'),
  mostAnswered('most_answered');

  const QuestionSort(this.api);
  final String api;
}

/// A product question (snake_case wire shape; author name is denormalized).
class Question {
  const Question({
    required this.id,
    required this.productId,
    required this.userId,
    required this.authorName,
    required this.body,
    required this.answerCount,
    required this.createdAt,
  });

  factory Question.fromJson(Map<String, dynamic> j) => Question(
        id: (j['id'] as num).toInt(),
        productId: (j['product_id'] as num?)?.toInt() ?? 0,
        userId: (j['user_id'] as num?)?.toInt() ?? 0,
        authorName: (j['author_name'] as String?) ?? '',
        body: (j['body'] as String?) ?? '',
        answerCount: (j['answer_count'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse((j['created_at'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  final int id;
  final int productId;
  final int userId;
  final String authorName;
  final String body;
  final int answerCount;
  final DateTime createdAt;
}

/// An answer to a question. [isSeller] drives the "Satıcı" badge.
class Answer {
  const Answer({
    required this.id,
    required this.questionId,
    required this.userId,
    required this.authorName,
    required this.isSeller,
    required this.body,
    required this.createdAt,
  });

  factory Answer.fromJson(Map<String, dynamic> j) => Answer(
        id: (j['id'] as num).toInt(),
        questionId: (j['question_id'] as num?)?.toInt() ?? 0,
        userId: (j['user_id'] as num?)?.toInt() ?? 0,
        authorName: (j['author_name'] as String?) ?? '',
        isSeller: (j['is_seller'] as bool?) ?? false,
        body: (j['body'] as String?) ?? '',
        createdAt: DateTime.tryParse((j['created_at'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  final int id;
  final int questionId;
  final int userId;
  final String authorName;
  final bool isSeller;
  final String body;
  final DateTime createdAt;
}

/// A question with its answers (GET /products/{id}/questions/{qid}).
class QuestionThread {
  const QuestionThread({required this.question, required this.answers});

  final Question question;
  final List<Answer> answers;
}

/// Thin wrapper over the Q&A endpoints. Reads are public; writes require auth.
class QaRepository {
  QaRepository(this._dio);

  final Dio _dio;

  Future<(List<Question>, int, bool)> listQuestions(
    int productId, {
    required QuestionSort sort,
    required int page,
    required int pageSize,
  }) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/products/$productId/questions',
      queryParameters: <String, dynamic>{
        'sort': sort.api,
        'page': page,
        'pageSize': pageSize,
      },
    );
    final data = resp.data ?? const {};
    final items = ((data['data'] as List<dynamic>?) ?? const [])
        .map((e) => Question.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = (data['total'] as num?)?.toInt() ?? items.length;
    final hasMore = (data['hasMore'] as bool?) ?? false;
    return (items, total, hasMore);
  }

  Future<QuestionThread> getThread(int productId, int questionId) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/products/$productId/questions/$questionId',
    );
    final data = resp.data ?? const {};
    final q = Question.fromJson(
      (data['question'] as Map<String, dynamic>?) ?? const {},
    );
    final answers = ((data['answers'] as List<dynamic>?) ?? const [])
        .map((e) => Answer.fromJson(e as Map<String, dynamic>))
        .toList();
    return QuestionThread(question: q, answers: answers);
  }

  Future<void> ask(
    int productId, {
    required String body,
    required String locale,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/products/$productId/questions',
      data: <String, dynamic>{'body': body, 'submittedLocale': locale},
    );
  }

  Future<void> answer(
    int productId,
    int questionId, {
    required String body,
    required String locale,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/products/$productId/questions/$questionId/answers',
      data: <String, dynamic>{'body': body, 'submittedLocale': locale},
    );
  }

  Future<(List<Question>, int, bool)> listMine({
    required int page,
    required int pageSize,
  }) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/me/questions',
      queryParameters: <String, dynamic>{'page': page, 'pageSize': pageSize},
    );
    final data = resp.data ?? const {};
    final items = ((data['data'] as List<dynamic>?) ?? const [])
        .map((e) => Question.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = (data['total'] as num?)?.toInt() ?? items.length;
    final hasMore = (data['hasMore'] as bool?) ?? false;
    return (items, total, hasMore);
  }
}

final qaRepositoryProvider = Provider<QaRepository>(
  (ref) => QaRepository(ref.watch(dioProvider)),
);

/// One question thread, keyed by `(productId, questionId)`. Auto-disposed;
/// invalidated after a successful answer submit.
final questionThreadProvider = FutureProvider.family
    .autoDispose<QuestionThread, (int, int)>((ref, key) {
  return ref.watch(qaRepositoryProvider).getThread(key.$1, key.$2);
});

// ── PDP / full questions list (paginated, sortable), keyed by productId ───────

class QuestionsState {
  const QuestionsState({
    this.items = const [],
    this.total = 0,
    this.page = 0,
    this.sort = QuestionSort.newest,
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = false,
    this.error,
  });

  final List<Question> items;
  final int total;
  final int page;
  final QuestionSort sort;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final Object? error;

  QuestionsState copyWith({
    List<Question>? items,
    int? total,
    int? page,
    QuestionSort? sort,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) =>
      QuestionsState(
        items: items ?? this.items,
        total: total ?? this.total,
        page: page ?? this.page,
        sort: sort ?? this.sort,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: clearError ? null : (error ?? this.error),
      );
}

class QuestionsNotifier extends FamilyNotifier<QuestionsState, int> {
  // Not `late final`: a family Notifier may rebuild (e.g. after invalidation),
  // re-running build() and reassigning this.
  late int _productId;

  @override
  QuestionsState build(int productId) {
    _productId = productId;
    Future<void>.microtask(() => _fetchFirstPage(QuestionSort.newest));
    return const QuestionsState();
  }

  QaRepository get _repo => ref.read(qaRepositoryProvider);

  Future<void> _fetchFirstPage(QuestionSort sort) async {
    state = state.copyWith(loading: true, sort: sort, clearError: true);
    try {
      final (items, total, hasMore) = await _repo.listQuestions(
        _productId,
        sort: sort,
        page: 1,
        pageSize: kQuestionsPageSize,
      );
      state = state.copyWith(
        items: items,
        total: total,
        page: 1,
        hasMore: hasMore,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> refresh() => _fetchFirstPage(state.sort);

  Future<void> setSort(QuestionSort sort) async {
    if (sort == state.sort && !state.loading && state.error == null) return;
    await _fetchFirstPage(sort);
  }

  Future<void> loadMore() async {
    if (state.loadingMore || state.loading || !state.hasMore) return;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final (items, total, hasMore) = await _repo.listQuestions(
        _productId,
        sort: state.sort,
        page: state.page + 1,
        pageSize: kQuestionsPageSize,
      );
      state = state.copyWith(
        items: [...state.items, ...items],
        total: total,
        page: state.page + 1,
        hasMore: hasMore,
        loadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false, error: e);
    }
  }
}

final questionsProvider =
    NotifierProvider.family<QuestionsNotifier, QuestionsState, int>(
  QuestionsNotifier.new,
);

// ── /account/questions (current user's own questions) ─────────────────────────

class MyQuestionsState {
  const MyQuestionsState({
    this.items = const [],
    this.total = 0,
    this.page = 0,
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = false,
    this.error,
  });

  final List<Question> items;
  final int total;
  final int page;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final Object? error;

  MyQuestionsState copyWith({
    List<Question>? items,
    int? total,
    int? page,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) =>
      MyQuestionsState(
        items: items ?? this.items,
        total: total ?? this.total,
        page: page ?? this.page,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: clearError ? null : (error ?? this.error),
      );
}

const int kMyQuestionsPageSize = 20;

class MyQuestionsNotifier extends Notifier<MyQuestionsState> {
  @override
  MyQuestionsState build() {
    Future<void>.microtask(refresh);
    return const MyQuestionsState();
  }

  QaRepository get _repo => ref.read(qaRepositoryProvider);

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final (items, total, hasMore) =
          await _repo.listMine(page: 1, pageSize: kMyQuestionsPageSize);
      state = MyQuestionsState(
        items: items,
        total: total,
        page: 1,
        loading: false,
        hasMore: hasMore,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || state.loading || !state.hasMore) return;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final (items, total, hasMore) = await _repo.listMine(
        page: state.page + 1,
        pageSize: kMyQuestionsPageSize,
      );
      state = state.copyWith(
        items: [...state.items, ...items],
        total: total,
        page: state.page + 1,
        hasMore: hasMore,
        loadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false, error: e);
    }
  }
}

final myQuestionsProvider =
    NotifierProvider<MyQuestionsNotifier, MyQuestionsState>(
  MyQuestionsNotifier.new,
);
