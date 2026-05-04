using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace NeeView
{
    public partial class SearchBoxModel : ObservableObject
    {
        private string? _keyword;
        private string? _keywordErrorMessage;
        private readonly ISearchBoxComponent _component;


        public SearchBoxModel(ISearchBoxComponent component)
        {
            _component = component;
        }


        /// <summary>
        /// 検索キーワード
        /// </summary>
        public string? Keyword
        {
            get { return _keyword; }
            set
            {
                if (SetProperty(ref _keyword, value))
                {
                    OnKeywordChanged();
                    OnPropertyChanged(nameof(FixedKeyword));
                }
            }
        }

        /// <summary>
        /// 検索キーワードの正規化
        /// </summary>
        public string FixedKeyword => _keyword?.Trim() ?? "";

        /// <summary>
        /// 検索キーワードエラーメッセージ
        /// </summary>
        public string? KeywordErrorMessage
        {
            get => _keywordErrorMessage;
            set => SetProperty(ref _keywordErrorMessage, value);
        }

        /// <summary>
        /// 検索キーワードエラー？
        /// </summary>
        public bool IsKeywordError => _keywordErrorMessage != null;

        /// <summary>
        /// 検索キーワード履歴
        /// </summary>
        public HistoryStringCollection? History => _component.History;

        /// <summary>
        /// インクリメンタルサーチフラグ
        /// </summary>
        public bool IsIncrementalSearchEnabled => _component.IsIncrementalSearchEnabled;


        /// <summary>
        /// キーワードプロパティ変更処理
        /// </summary>
        private void OnKeywordChanged()
        {
            var keyword = FixedKeyword;

            var result = _component.Analyze(keyword);
            KeywordErrorMessage = result.Exception?.Message;

            if (result.IsSuccess)
            {
                IncrementalSearch();
            }
        }

        /// <summary>
        /// 検索実行
        /// </summary>
        [RelayCommand]
        public void Search()
        {
            if (IsKeywordError) return;

            // 検索を重複させないための処置
            if (!IsIncrementalSearchEnabled)
            {
                _component.Search(FixedKeyword);
            }

            // 確定検索なので履歴更新
            UpdateSearchHistory();
        }

        /// <summary>
        /// 逐次検索
        /// </summary>
        private void IncrementalSearch()
        {
            if (IsKeywordError) return;

            //Debug.WriteLine($"Search: {_searchKeyword.Value}");
            // インクリメンタルサーチなら検索実行
            if (IsIncrementalSearchEnabled)
            {
                _component.Search(FixedKeyword);
            }
        }

        /// <summary>
        /// 検索履歴更新
        /// </summary>
        public void UpdateSearchHistory()
        {
            if (IsKeywordError) return;

            var keyword = FixedKeyword;
            if (string.IsNullOrEmpty(keyword)) return;
            History?.Append(keyword);
        }

        /// <summary>
        /// 履歴削除
        /// </summary>
        /// <param name="keyword"></param>
        [RelayCommand]
        public void Delete(string? keyword)
        {
            if (string.IsNullOrEmpty(keyword)) return;
            History?.Remove(keyword);
        }

        /// <summary>
        /// 環境変更による検索キーワードリセット
        /// </summary>
        /// <param name="keyword"></param>
        public void ResetInputKeyword(string? keyword)
        {
            if (keyword != FixedKeyword)
            {
                UpdateSearchHistory();
                // 入力文字のみ更新
                _keyword = keyword;
                OnPropertyChanged(nameof(Keyword));
            }
        }
    }


}
