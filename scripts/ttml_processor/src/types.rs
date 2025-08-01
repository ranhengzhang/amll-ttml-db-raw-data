//! 定义了歌词转换中使用的核心数据类型。

use std::{collections::HashMap, fmt, io, str::FromStr};

use quick_xml::{
    Error as QuickXmlErrorMain, encoding::EncodingError,
    events::attributes::AttrError as QuickXmlAttrError,
};
use serde::{Deserialize, Serialize};
use strum_macros::EnumString;
use thiserror::Error;

//=============================================================================
// 1. 错误枚举
//=============================================================================

/// 定义歌词转换和处理过程中可能发生的各种错误。
#[derive(Error, Debug)]
pub enum ConvertError {
    /// XML 解析或生成错误，通常来自 `quick-xml` 库。
    #[error("生成或解析 XML 时出错: {0}")]
    Xml(#[from] QuickXmlErrorMain),

    /// XML 属性解析错误，当读取或解析标签属性时发生。
    #[error("处理 XML 属性时出错: {0}")]
    Attribute(#[from] QuickXmlAttrError),

    /// 字符串到整数的解析失败。
    #[error("解析整数失败: {0}")]
    ParseInt(#[from] std::num::ParseIntError),

    /// 时间戳字符串格式不符合 TTML 或其他预期标准。
    #[error("无效的时间格式: {0}")]
    InvalidTime(String),

    /// 字符串格式化操作失败。
    #[error("字符串格式化失败: {0}")]
    Format(#[from] std::fmt::Error),

    /// 表示程序内部逻辑错误或未明确分类的运行时错误。
    #[error("内部逻辑错误: {0}")]
    Internal(String),

    /// 文件读写等输入/输出操作失败。
    #[error("IO 错误: {0}")]
    Io(#[from] io::Error),

    /// 字节序列无法安全地转换为 UTF-8 编码的字符串。
    #[error("UTF-8 编码转换错误: {0}")]
    FromUtf8(#[from] std::string::FromUtf8Error),

    /// XML 文本编码或解码错误。
    #[error("文本编码或解码错误: {0}")]
    Encoding(#[from] EncodingError),
}

/// 定义从字符串解析 `CanonicalMetadataKey` 时可能发生的错误。
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct ParseCanonicalMetadataKeyError(String); // 存储无法解析的原始键字符串

impl std::fmt::Display for ParseCanonicalMetadataKeyError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "未知或无效的元数据键: {}", self.0)
    }
}
impl std::error::Error for ParseCanonicalMetadataKeyError {}

//=============================================================================
// 2. 核心歌词格式枚举及相关
//=============================================================================

/// 枚举：表示支持的歌词格式。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, EnumString, Serialize, Deserialize)]
#[strum(ascii_case_insensitive)]
#[derive(Default)]
pub enum LyricFormat {
    #[default]
    Ttml,
}

//=============================================================================
// 3. 歌词内部表示结构
//=============================================================================

/// 通用的歌词音节结构，用于表示逐字歌词中的一个音节。
#[derive(Default, Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LyricSyllable {
    /// 音节的文本内容。
    pub text: String,
    /// 音节开始时间，相对于歌曲开始的绝对时间（毫秒）。
    pub start_ms: u64,
    /// 音节结束时间，相对于歌曲开始的绝对时间（毫秒）。
    pub end_ms: u64,
    /// 可选的音节持续时间（毫秒）。
    /// 如果提供，`end_ms` 可以由 `start_ms + duration_ms` 计算得出，反之亦然。
    /// 解析器应确保 `start_ms` 和 `end_ms` 最终被填充。
    pub duration_ms: Option<u64>,
    /// 指示该音节后是否应有空格。
    pub ends_with_space: bool,
}

/// 表示单个翻译及其语言的结构体。
#[derive(Debug, Default, Clone, PartialEq, Serialize, Deserialize)]
pub struct TranslationEntry {
    /// 翻译的文本内容。
    pub text: String,
    /// 翻译的语言代码，可选。
    /// 建议遵循 BCP 47 标准 (例如 "en", "ja", "zh-Hans")。
    pub lang: Option<String>,
}

/// 表示单个罗马音及其语言/方案的结构体。
#[derive(Debug, Default, Clone, PartialEq, Serialize, Deserialize)]
pub struct RomanizationEntry {
    /// 罗马音的文本内容。
    pub text: String,
    /// 目标音译的语言和脚本代码，可选。
    /// 例如 "ja-Latn" (日语罗马字), "ko-Latn" (韩语罗马字)。
    pub lang: Option<String>,
    /// 可选的特定罗马音方案名称。
    /// 例如 "Hepburn" (平文式罗马字), "Nihon-shiki" (日本式罗马字), "RevisedRomanization" (韩语罗马字修正案)。
    pub scheme: Option<String>,
}

/// 表示歌词行中的背景歌词部分。
#[derive(Debug, Default, Clone, PartialEq, Serialize, Deserialize)]
pub struct BackgroundSection {
    /// 背景歌词的开始时间（毫秒）。
    pub start_ms: u64,
    /// 背景歌词的结束时间（毫秒）。
    pub end_ms: u64,
    /// 背景歌词的音节列表。
    pub syllables: Vec<LyricSyllable>,
    /// 背景歌词的翻译。
    pub translations: Vec<TranslationEntry>,
    /// 背景歌词的罗马音。
    pub romanizations: Vec<RomanizationEntry>,
}

/// 通用的歌词行结构，作为项目内部处理歌词数据的主要表示。
#[derive(Debug, Default, Clone, PartialEq, Serialize, Deserialize)]
pub struct LyricLine {
    /// 行的开始时间，相对于歌曲开始的绝对时间（毫秒）。
    pub start_ms: u64,
    /// 行的结束时间，相对于歌曲开始的绝对时间（毫秒）。
    pub end_ms: u64,
    /// 可选的整行文本内容。
    /// 主要用于纯逐行歌词格式（如标准LRC）。
    pub line_text: Option<String>,
    /// 主歌词的音节列表。
    pub main_syllables: Vec<LyricSyllable>,
    /// 该行的翻译列表。
    pub translations: Vec<TranslationEntry>,
    /// 该行的罗马音列表。
    pub romanizations: Vec<RomanizationEntry>,
    /// 可选的演唱者标识。
    /// 通常情况下应确保至少有一个 `v1`。
    pub agent: Option<String>,
    /// 可选的背景歌词部分。
    pub background_section: Option<BackgroundSection>,
    /// 可选的歌曲组成部分标记。
    /// 例如 "verse", "chorus", "bridge"。
    pub song_part: Option<String>,
    /// 可选的 iTunes Key (如 "L1", "L2")。
    pub itunes_key: Option<String>,
}

//=============================================================================
// 4. 元数据结构体
//=============================================================================

/// 定义元数据的规范化键。
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum CanonicalMetadataKey {
    /// 歌曲标题。
    Title,
    /// 艺术家。
    Artist,
    /// 专辑名。
    Album,
    /// 主歌词的语言代码 (BCP 47)。
    Language,
    /// 全局时间偏移量（毫秒）。
    Offset,
    /// 词曲作者。
    Songwriter,
    /// 网易云音乐 ID。
    NcmMusicId,
    /// QQ音乐 ID。
    QqMusicId,
    /// Spotify ID。
    SpotifyId,
    /// Apple Music ID。
    AppleMusicId,
    /// 国际标准音像制品编码 (International Standard Recording Code)。
    Isrc,
    /// TTML歌词贡献者的GitHubID。
    TtmlAuthorGithub,
    /// TTML歌词贡献者的GitHub登录名。
    TtmlAuthorGithubLogin,

    /// 用于所有其他未明确定义的标准或非标准元数据键。
    Custom(String),
}

impl fmt::Display for CanonicalMetadataKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let key_name = match self {
            CanonicalMetadataKey::Title => "Title",
            CanonicalMetadataKey::Artist => "Artist",
            CanonicalMetadataKey::Album => "Album",
            CanonicalMetadataKey::Language => "Language",
            CanonicalMetadataKey::Offset => "Offset",
            CanonicalMetadataKey::Songwriter => "Songwriter",
            CanonicalMetadataKey::NcmMusicId => "NcmMusicId",
            CanonicalMetadataKey::QqMusicId => "QqMusicId",
            CanonicalMetadataKey::SpotifyId => "SpotifyId",
            CanonicalMetadataKey::AppleMusicId => "AppleMusicId",
            CanonicalMetadataKey::Isrc => "Isrc",
            CanonicalMetadataKey::TtmlAuthorGithub => "TtmlAuthorGithub",
            CanonicalMetadataKey::TtmlAuthorGithubLogin => "TtmlAuthorGithubLogin",
            CanonicalMetadataKey::Custom(s) => s.as_str(),
        };
        write!(f, "{key_name}")
    }
}

impl CanonicalMetadataKey {
    /// 定义哪些键应该被显示出来
    pub fn is_public(&self) -> bool {
        matches!(
            self,
            Self::Title
                | Self::Artist
                | Self::Album
                | Self::NcmMusicId
                | Self::QqMusicId
                | Self::SpotifyId
                | Self::AppleMusicId
                | Self::Isrc
                | Self::TtmlAuthorGithub
                | Self::TtmlAuthorGithubLogin
        )
    }
}

impl FromStr for CanonicalMetadataKey {
    type Err = ParseCanonicalMetadataKeyError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "ti" | "title" | "musicname" => Ok(Self::Title),
            "ar" | "artist" | "artists" => Ok(Self::Artist),
            "al" | "album" => Ok(Self::Album),
            "by" | "ttmlauthorgithublogin" => Ok(Self::TtmlAuthorGithubLogin),
            "language" | "lang" => Ok(Self::Language),
            "offset" => Ok(Self::Offset),
            "songwriter" | "songwriters" => Ok(Self::Songwriter),
            "ncmmusicid" => Ok(Self::NcmMusicId),
            "qqmusicid" => Ok(Self::QqMusicId),
            "spotifyid" => Ok(Self::SpotifyId),
            "applemusicid" => Ok(Self::AppleMusicId),
            "isrc" => Ok(Self::Isrc),
            "ttmlauthorgithub" => Ok(Self::TtmlAuthorGithub),
            custom_key if !custom_key.is_empty() => Ok(Self::Custom(custom_key.to_string())),
            _ => Err(ParseCanonicalMetadataKeyError(s.to_string())),
        }
    }
}

//=============================================================================
// 5. 处理与数据结构体
//=============================================================================

/// 存储从源文件解析出的、准备进行进一步处理或转换的歌词数据。
/// 这是解析阶段的主要输出，也是后续处理和生成阶段的主要输入。
#[derive(Debug, Default, Clone, Serialize, Deserialize, PartialEq)]
pub struct ParsedSourceData {
    /// 解析后的歌词行列表。
    pub lines: Vec<LyricLine>,
    /// 从文件头或特定元数据标签中解析出的原始（未规范化）元数据。
    /// 键是原始元数据标签名，值是该标签对应的所有值（因为某些标签可能出现多次）。
    pub raw_metadata: HashMap<String, Vec<String>>,
    /// 解析的源文件格式。
    pub source_format: LyricFormat,
    /// 可选的原始文件名，可用于日志记录或某些特定转换逻辑。
    pub source_filename: Option<String>,
    /// 指示源文件是否是逐行歌词（例如LRC）。
    pub is_line_timed_source: bool,
    /// 解析过程中产生的警告信息列表。
    pub warnings: Vec<String>,
    /// 如果源文件是内嵌TTML的JSON，此字段存储原始的TTML字符串内容。
    pub raw_ttml_from_input: Option<String>,
    /// 指示输入的TTML（来自`raw_ttml_from_input`）是否被格式化。
    /// 这影响空格和换行的处理。
    pub detected_formatted_ttml_input: Option<bool>,
    /// 提供商名称
    pub source_name: String,
}

//=============================================================================
// 6. 辅助类型与函数
//=============================================================================

/// 表示从ASS中提取的标记信息。
/// 元组的第一个元素是原始行号，第二个元素是标记文本。
pub type MarkerInfo = (usize, String);

/// TTML 生成时的计时模式
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum TtmlTimingMode {
    #[default]
    /// 逐字计时
    Word,
    /// 逐行计时
    Line,
}

/// TTML 解析选项
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TtmlParsingOptions {
    /// 当TTML本身未指定语言时，解析器可以使用的默认语言。
    #[serde(default)]
    pub default_languages: DefaultLanguageOptions,

    /// 强制指定计时模式，忽略文件内的 `itunes:timing` 属性和自动检测逻辑。
    #[serde(default)]
    pub force_timing_mode: Option<TtmlTimingMode>,
}

/// TTML 生成选项
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TtmlGenerationOptions {
    /// 生成的计时模式（逐字或逐行）。
    pub timing_mode: TtmlTimingMode,
    /// 指定输出 TTML 的主语言 (xml:lang)。如果为 None，则尝试从元数据推断。
    pub main_language: Option<String>,
    /// 为内联的翻译 `<span>` 指定默认语言代码。
    pub translation_language: Option<String>,
    /// 为内联的罗马音 `<span>` 指定默认语言代码。
    pub romanization_language: Option<String>,
    /// 是否遵循 Apple Music 的特定格式规则（例如，将翻译写入`<head>`而不是内联）。
    pub use_apple_format_rules: bool,
    /// 是否输出格式化的 TTML 文件。
    pub format: bool,
    /// 是否启用自动分词功能。
    pub auto_word_splitting: bool,
    /// 自动分词时，一个标点符号所占的权重（一个字符的权重为1.0）。
    pub punctuation_weight: f64,
}

impl Default for TtmlGenerationOptions {
    fn default() -> Self {
        Self {
            timing_mode: TtmlTimingMode::Word,
            main_language: None,
            translation_language: None,
            romanization_language: None,
            use_apple_format_rules: false,
            format: false,
            auto_word_splitting: false,
            punctuation_weight: 0.3,
        }
    }
}

/// TTML 解析时使用的默认语言选项
/// 当TTML本身未指定语言时，解析器可以使用这些值。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DefaultLanguageOptions {
    /// 默认主语言代码
    pub main: Option<String>,
    /// 默认翻译语言代码
    pub translation: Option<String>,
    /// 默认罗马音语言代码
    pub romanization: Option<String>,
}

// =============================================================================
// 9. 平滑优化选项
// =============================================================================

/// 控制平滑优化的选项。
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct SyllableSmoothingOptions {
    /// 用于平滑的因子 (0.0 ~ 0.5)。
    pub factor: f64,
    /// 用于分组的时长差异阈值（毫秒）。
    pub duration_threshold_ms: u64,
    /// 用于分组的间隔阈值（毫秒）。
    pub gap_threshold_ms: u64,
    /// 组内平滑的次数。
    pub smoothing_iterations: u32,
}

impl Default for SyllableSmoothingOptions {
    fn default() -> Self {
        Self {
            factor: 0.15,
            duration_threshold_ms: 50,
            gap_threshold_ms: 100,
            smoothing_iterations: 5,
        }
    }
}
