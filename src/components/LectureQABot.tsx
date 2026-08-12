import React, { useState } from 'react';
import type { QAMessage, TargetLanguage, Lecture } from '../types';
import { getLanguageInfo } from '../types';
import { Send, Bot, User, Sparkles, HelpCircle, Loader2 } from 'lucide-react';
import { askLectureAI } from '../services/aiService';

interface LectureQABotProps {
  lecture: Lecture;
  targetLang: TargetLanguage;
}

export const LectureQABot: React.FC<LectureQABotProps> = ({ lecture, targetLang }) => {
  const [messages, setMessages] = useState<QAMessage[]>([
    {
      id: 'init-1',
      sender: 'ai',
      text:
        targetLang === 'hi'
          ? 'नमस्ते! मैं आपका स्मार्ट क्लासरूम AI सहायक हूँ। इस व्याख्यान, स्लाइडों या सूत्रों के बारे में कुछ भी पूछें!'
          : targetLang === 'bn'
          ? 'হ্যালো! আমি আপনার স্মার্ট ক্লাসরুম এআই সহকারী। আজকের লেকচার, গ্রাফ বা সূত্র নিয়ে যেকোনো প্রশ্ন করুন!'
          : targetLang === 'ar'
          ? 'مرحباً! أنا مساعدك الذكي في الفصل الدراسي. اسألني أي شيء عن المحاضرة، الرسوم البيانية، أو الصيغ!'
          : 'Hello! I am your Smart Classroom AI Assistant. Ask me any question about today’s lecture, board slides, or formulas!',
      language: targetLang,
      timestamp: 'Just now'
    }
  ]);
  const [inputText, setInputText] = useState('');
  const [loading, setLoading] = useState(false);

  const langInfo = getLanguageInfo(targetLang);

  const concept = lecture.notes.keyConcepts[targetLang]?.[0]?.concept
    || lecture.pages[0]?.title
    || lecture.title;
  const suggestedQuestions = ({
    en: [
      `What is ${concept}?`,
      'Summarize the main ideas from this lecture.',
      'Explain the most important formula or diagram.'
    ],
    hi: [
      `${concept} क्या है?`,
      'इस व्याख्यान के मुख्य विचारों का सारांश दें।',
      'सबसे महत्वपूर्ण सूत्र या आरेख समझाइए।'
    ],
    bn: [
      `${concept} কী?`,
      'এই লেকচারের মূল ধারণাগুলোর সারাংশ দিন।',
      'সবচেয়ে গুরুত্বপূর্ণ সূত্র বা চিত্রটি ব্যাখ্যা করুন।'
    ],
    ar: [
      `ما هو ${concept}؟`,
      'لخّص الأفكار الرئيسية في هذه المحاضرة.',
      'اشرح أهم صيغة أو رسم توضيحي.'
    ]
  }[targetLang] || [
    `What is ${concept}?`,
    'Summarize the main ideas from this lecture.',
    'Explain the most important formula or diagram.'
  ]);

  const handleSend = async (textToSend?: string) => {
    const query = textToSend || inputText;
    if (!query.trim() || loading) return;

    const userMsg: QAMessage = {
      id: `user-${Date.now()}`,
      sender: 'user',
      text: query,
      language: targetLang,
      timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
    };

    setMessages((prev) => [...prev, userMsg]);
    if (!textToSend) setInputText('');
    setLoading(true);

    try {
      const aiReply = await askLectureAI(query, targetLang, lecture, messages);
      setMessages((prev) => [...prev, aiReply]);
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="card-chat-assistant space-y-4">
      
      {/* Header */}
      <div className="flex items-center justify-between border-b border-slate-200 pb-3">
        <div className="flex items-center gap-2.5">
          <div className="w-8 h-8 rounded-xl bg-blue-100 text-blue-700 flex items-center justify-center border border-blue-200">
            <Bot className="w-4 h-4" />
          </div>
          <div>
            <h3 className="text-xs font-bold text-slate-900 flex items-center gap-1.5">
              <span>AI Classroom Tutor Assistant</span>
              <span className="text-[10px] bg-blue-100 text-blue-800 border border-blue-200 px-2 py-0.5 rounded-full font-mono font-bold">
                {langInfo.flag} {langInfo.name}
              </span>
            </h3>
            <p className="text-[11px] text-slate-500">Ask questions in your native language about the lecture</p>
          </div>
        </div>
      </div>

      {/* Suggested Quick Questions */}
      <div className="space-y-1.5">
        <span className="text-[10px] text-slate-400 uppercase font-bold tracking-wider flex items-center gap-1">
          <HelpCircle className="w-3.5 h-3.5 text-blue-600" />
          Suggested Questions:
        </span>
        <div className="flex flex-wrap gap-1.5">
          {suggestedQuestions.map((q, idx) => (
            <button
              key={idx}
              type="button"
              onClick={() => handleSend(q)}
              className="chip-suggested-q"
            >
              {q}
            </button>
          ))}
        </div>
      </div>

      {/* Messages Feed */}
      <div className="space-y-3 max-h-[320px] overflow-y-auto pr-1">
        {messages.map((m) => (
          <div
            key={m.id}
            className={`flex items-start gap-2.5 ${
              m.sender === 'user' ? 'flex-row-reverse' : ''
            }`}
          >
            <div
              className={`w-7 h-7 rounded-full flex items-center justify-center shrink-0 text-xs font-bold ${
                m.sender === 'user'
                  ? 'bg-blue-600 text-white'
                  : 'bg-blue-100 text-blue-700 border border-blue-200'
              }`}
            >
              {m.sender === 'user' ? <User className="w-3.5 h-3.5" /> : <Sparkles className="w-3.5 h-3.5" />}
            </div>

            <div
              dir={langInfo.dir}
              className={`max-w-[85%] ${m.sender === 'user' ? 'bubble-user' : 'bubble-ai'}`}
              style={{ fontFamily: langInfo.fontFamily }}
            >
              <p>{m.text}</p>
              <span className="text-[9px] opacity-60 block text-right font-mono mt-1">
                {m.timestamp}
              </span>
            </div>
          </div>
        ))}

        {loading && (
          <div className="flex items-center gap-2 text-xs text-blue-700 p-2.5 bg-blue-50 rounded-xl border border-blue-200 font-medium">
            <Loader2 className="w-4 h-4 animate-spin text-blue-600" />
            <span>AI Tutor is analyzing lecture context...</span>
          </div>
        )}
      </div>

      {/* Input Form */}
      <form
        onSubmit={(e) => {
          e.preventDefault();
          handleSend();
        }}
        className="flex items-center gap-2 pt-2"
      >
        <input
          type="text"
          value={inputText}
          onChange={(e) => setInputText(e.target.value)}
          placeholder={`Ask a question in ${langInfo.name}...`}
          className="input-chat-box font-medium"
          dir={langInfo.dir}
          style={{ fontFamily: langInfo.fontFamily }}
        />
        <button
          type="submit"
          disabled={!inputText.trim() || loading}
          className="btn-chat-send disabled:opacity-30 disabled:cursor-not-allowed"
        >
          <Send className="w-4 h-4" />
        </button>
      </form>

    </div>
  );
};
