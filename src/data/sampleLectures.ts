import type { Lecture } from '../types';

export const SAMPLE_LECTURES: Lecture[] = [
  {
    id: 'cs-101-bst',
    title: 'Binary Search Trees & Algorithmic Complexity',
    subject: 'Computer Science & Data Structures',
    instructor: 'Prof. Alan Turing',
    date: '2026-08-12',
    duration: '45 mins',
    pages: [
      {
        id: 'page-1',
        pageNumber: 1,
        title: 'BST Structure & Searching Logic',
        timestamp: '02:15',
        boardImageSvg: `<svg viewBox="0 0 800 500" width="100%" height="100%" xmlns="http://www.w3.org/2000/svg">
          <!-- Whiteboard background -->
          <rect width="800" height="500" fill="#0f172a" rx="12"/>
          <grid width="800" height="500" fill="none" stroke="#1e293b" stroke-width="1"/>
          
          <!-- Board Header -->
          <text x="30" y="45" fill="#38bdf8" font-family="'Courier New', monospace" font-size="22" font-weight="bold">CS201: Binary Search Tree (BST) Properties</text>
          <line x1="30" y1="55" x2="770" y2="55" stroke="#334155" stroke-width="2"/>
          
          <!-- Handwritten notes simulation -->
          <text x="40" y="95" fill="#f43f5e" font-family="sans-serif" font-size="16" font-weight="bold">Rule: Left &lt; Root &lt; Right</text>
          <text x="40" y="120" fill="#94a3b8" font-family="sans-serif" font-size="14">• Every node has at most 2 children</text>
          <text x="40" y="145" fill="#94a3b8" font-family="sans-serif" font-size="14">• Searching takes O(h) time where h = height</text>
          
          <!-- Rough Whiteboard Diagram Drawing (Teacher's BST) -->
          <g stroke="#f59e0b" stroke-width="3" fill="none" stroke-linecap="round">
            <!-- Root 15 -->
            <circle cx="520" cy="120" r="28" stroke="#38bdf8" fill="#1e293b"/>
            <text x="520" y="126" fill="#e2e8f0" font-family="monospace" font-size="18" font-weight="bold" text-anchor="middle">15</text>
            
            <!-- Branches -->
            <path d="M 500 140 L 420 190" stroke="#f59e0b"/>
            <path d="M 540 140 L 620 190" stroke="#f59e0b"/>
            
            <!-- Left Child 10 -->
            <circle cx="420" cy="210" r="24" stroke="#38bdf8" fill="#1e293b"/>
            <text x="420" y="216" fill="#e2e8f0" font-family="monospace" font-size="16" text-anchor="middle">10</text>
            
            <!-- Right Child 25 -->
            <circle cx="620" cy="210" r="24" stroke="#38bdf8" fill="#1e293b"/>
            <text x="620" y="216" fill="#e2e8f0" font-family="monospace" font-size="16" text-anchor="middle">25</text>
            
            <!-- Sub branches -->
            <path d="M 405 230 L 360 270" stroke="#f59e0b"/>
            <path d="M 435 230 L 470 270" stroke="#f59e0b"/>
            
            <!-- Leaf 5 -->
            <circle cx="360" cy="290" r="20" stroke="#34d399" fill="#1e293b"/>
            <text x="360" y="295" fill="#e2e8f0" font-family="monospace" font-size="14" text-anchor="middle">5</text>

            <!-- Leaf 12 -->
            <circle cx="470" cy="290" r="20" stroke="#34d399" fill="#1e293b"/>
            <text x="470" y="295" fill="#e2e8f0" font-family="monospace" font-size="14" text-anchor="middle">12</text>
          </g>

          <!-- Annotations & Formulas -->
          <rect x="40" y="190" width="300" height="130" fill="#1e293b" rx="8" stroke="#334155"/>
          <text x="55" y="220" fill="#a78bfa" font-family="sans-serif" font-size="16" font-weight="bold">Height Calculation Formula:</text>
          <text x="55" y="255" fill="#facc15" font-family="serif" font-size="18" font-style="italic">h = ⌊ log₂ (N + 1) ⌋ - 1</text>
          <text x="55" y="290" fill="#64748b" font-family="sans-serif" font-size="13">Best case height for N=7 nodes is h = 2</text>
          
          <!-- Teacher's messy handwritten note -->
          <path d="M 350 350 C 370 330, 420 370, 450 340" stroke="#ef4444" stroke-width="2" fill="none"/>
          <text x="40" y="420" fill="#ef4444" font-family="sans-serif" font-size="15" font-weight="bold">⚠️ Skewed Tree degradation: O(N) Worst Case!</text>
        </svg>`,
        handwrittenNotes: [
          'Rule: Left subtree < Root < Right subtree',
          'Searching time is directly proportional to height: O(h)',
          'Formula for min height: h = log2(N)',
          'Degenerate tree becomes a linked list -> O(N) lookup'
        ],
        extractedText: 'CS201: Binary Search Tree (BST) Properties. Rule: Left < Root < Right. Height Calculation Formula: h = log2(N+1)-1. Best case height for N=7 nodes is h=2. Skewed Tree degradation: O(N) Worst Case!',
        diagrams: [
          {
            id: 'diag-bst-tree',
            title: 'Binary Search Tree Hierarchy & Balancing',
            type: 'tree',
            roughSketchSvg: `<svg viewBox="0 0 400 300" xmlns="http://www.w3.org/2000/svg">
              <rect width="400" height="300" fill="#18181b" rx="8"/>
              <text x="20" y="30" fill="#ef4444" font-size="14" font-family="monospace">[Teacher's Rough Board Drawing]</text>
              <circle cx="200" cy="80" r="22" stroke="#e4e4e7" stroke-width="2" fill="none"/>
              <text x="200" y="85" fill="#fff" text-anchor="middle">15</text>
              <line x1="180" y1="100" x2="120" y2="150" stroke="#e4e4e7" stroke-width="2"/>
              <line x1="220" y1="100" x2="280" y2="150" stroke="#e4e4e7" stroke-width="2"/>
              <circle cx="120" cy="170" r="18" stroke="#e4e4e7" stroke-width="2" fill="none"/>
              <text x="120" y="175" fill="#fff" text-anchor="middle">10</text>
              <circle cx="280" cy="170" r="18" stroke="#e4e4e7" stroke-width="2" fill="none"/>
              <text x="280" y="175" fill="#fff" text-anchor="middle">25</text>
              <path d="M 80 230 Q 120 200 160 230" stroke="#f59e0b" fill="none" stroke-dasharray="4"/>
              <text x="120" y="260" fill="#f59e0b" font-size="12" text-anchor="middle">Left Subtree &lt; 15</text>
            </svg>`,
            cleanDiagramSvg: `<svg viewBox="0 0 400 300" xmlns="http://www.w3.org/2000/svg">
              <defs>
                <linearGradient id="nodeGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" stop-color="#3b82f6"/>
                  <stop offset="100%" stop-color="#1d4ed8"/>
                </linearGradient>
                <linearGradient id="leafGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" stop-color="#10b981"/>
                  <stop offset="100%" stop-color="#047857"/>
                </linearGradient>
              </defs>
              <rect width="400" height="300" fill="#0f172a" rx="8" stroke="#1e293b"/>
              <text x="20" y="30" fill="#10b981" font-size="14" font-weight="bold" font-family="sans-serif">✓ AI Cleaned-Up Vector Diagram</text>
              
              <!-- Clean Tree Links -->
              <line x1="200" y1="75" x2="120" y2="145" stroke="#38bdf8" stroke-width="3"/>
              <line x1="200" y1="75" x2="280" y2="145" stroke="#38bdf8" stroke-width="3"/>
              <line x1="120" y1="145" x2="70" y2="215" stroke="#38bdf8" stroke-width="2.5"/>
              <line x1="120" y1="145" x2="170" y2="215" stroke="#38bdf8" stroke-width="2.5"/>

              <!-- Nodes -->
              <circle cx="200" cy="75" r="24" fill="url(#nodeGrad)" filter="drop-shadow(0 4px 6px rgba(0,0,0,0.3))"/>
              <text x="200" y="81" fill="#ffffff" font-weight="bold" font-size="16" text-anchor="middle" font-family="sans-serif">15</text>
              
              <circle cx="120" cy="145" r="20" fill="url(#nodeGrad)"/>
              <text x="120" y="150" fill="#ffffff" font-weight="bold" font-size="14" text-anchor="middle" font-family="sans-serif">10</text>

              <circle cx="280" cy="145" r="20" fill="url(#nodeGrad)"/>
              <text x="280" y="150" fill="#ffffff" font-weight="bold" font-size="14" text-anchor="middle" font-family="sans-serif">25</text>

              <circle cx="70" cy="215" r="18" fill="url(#leafGrad)"/>
              <text x="70" y="219" fill="#ffffff" font-weight="bold" font-size="13" text-anchor="middle" font-family="sans-serif">5</text>

              <circle cx="170" cy="215" r="18" fill="url(#leafGrad)"/>
              <text x="170" y="219" fill="#ffffff" font-weight="bold" font-size="13" text-anchor="middle" font-family="sans-serif">12</text>

              <!-- Level indicators -->
              <text x="350" y="78" fill="#64748b" font-size="11" text-anchor="end">Level 0 (Root)</text>
              <text x="350" y="148" fill="#64748b" font-size="11" text-anchor="end">Level 1</text>
              <text x="350" y="218" fill="#64748b" font-size="11" text-anchor="end">Level 2 (Leaves)</text>
            </svg>`,
            explanations: {
              en: 'A Binary Search Tree (BST) organizes data hierarchically. For any node N, all values in its left subtree are strictly smaller than N, and all values in its right subtree are strictly greater.',
              hi: 'बाइनरी सर्च ट्री (BST) डेटा को पदानुक्रमित (hierarchical) रूप से व्यवस्थित करता है। किसी भी नोड N के लिए, इसके बाएं सब-ट्री के सभी मान N से छोटे होते हैं, और दाएं सब-ट्री के मान बड़े होते हैं।',
              bn: 'বাইনারি সার্চ ট্রি (BST) ডেটাকে ক্রমানুসারে সাজায়। যেকোনো নোড N-এর জন্য, এর বাম সাব-ট্রির সমস্ত মান N-এর চেয়ে ছোট এবং ডান সাব-ট্রির মানগুলি N-এর চেয়ে বড় হয়।',
              ar: 'تُنظّم شجرة البحث الثنائية (BST) البيانات بشكل هرمي. لأي عقدة N، تكون جميع القيم في الشجرة الفرعية اليسرى أصغر من N، وجميع القيم في الشجرة الفرعية اليمنى أكبر من N.'
            },
            keyTakeaways: {
              en: [
                'Left child value < Parent node value',
                'Right child value > Parent node value',
                'Searching takes O(log N) operations in a balanced tree'
              ],
              hi: [
                'बाएं नोड का मान < पेरेंट नोड का मान',
                'दाएं नोड का मान > पेरेंट नोड का मान',
                'संतुलित ट्री में सर्चिंग O(log N) समय लेती है'
              ],
              bn: [
                'বাম চাইল্ডের মান < প্যারেন্ট নোডের মান',
                'ডান চাইল্ডের মান > প্যারেন্ট নোডের মান',
                'ভারসাম্যপূর্ণ ট্রিতে খোঁজার সময় O(log N) লাগে'
              ],
              ar: [
                'قيمة العقدة اليسرى < قيمة العقدة الأصلية',
                'قيمة العقدة اليمنى > قيمة العقدة الأصلية',
                'تستغرق عملية البحث O(log N) في الشجرة المتوازنة'
              ]
            }
          }
        ],
        formulas: [
          {
            id: 'form-1',
            latex: 'h = \\lfloor \\log_2 N \\rfloor',
            description: {
              en: 'Minimum height of a balanced Binary Search Tree containing N nodes.',
              hi: 'N नोड्स वाले संतुलित बाइनरी सर्च ट्री की न्यूनतम ऊंचाई (Minimum Height)।',
              bn: 'N টি নোড বিশিষ্ট একটি ভারসাম্যপূর্ণ বাইনারি সার্চ ট্রির সর্বনিম্ন উচ্চতা।',
              ar: 'الارتفاع الأدنى لشجرة البحث الثنائية المتوازنة التي تحتوي على N من العقد.'
            },
            variableBreakdown: {
              en: { h: 'Height of the tree', N: 'Total number of nodes' },
              hi: { h: 'ट्री की ऊंचाई (Height)', N: 'नोड्स की कुल संख्या' },
              bn: { h: 'ট্রির উচ্চতা', N: 'মোট নোডের সংখ্যা' },
              ar: { h: 'ارتفاع الشجرة', N: 'إجمالي عدد العقد' }
            }
          }
        ]
      },
      {
        id: 'page-2',
        pageNumber: 2,
        title: 'Time Complexity Curve Comparison',
        timestamp: '14:30',
        boardImageSvg: `<svg viewBox="0 0 800 500" width="100%" height="100%" xmlns="http://www.w3.org/2000/svg">
          <rect width="800" height="500" fill="#0f172a" rx="12"/>
          <text x="30" y="45" fill="#38bdf8" font-family="'Courier New', monospace" font-size="22" font-weight="bold">Big-O Complexity Comparison Graph</text>
          <line x1="30" y1="55" x2="770" y2="55" stroke="#334155" stroke-width="2"/>
          
          <!-- Graph Axes -->
          <line x1="100" y1="400" x2="700" y2="400" stroke="#94a3b8" stroke-width="3"/>
          <line x1="100" y1="400" x2="100" y2="100" stroke="#94a3b8" stroke-width="3"/>
          <text x="680" y="435" fill="#94a3b8" font-size="14" font-family="sans-serif">Input Size (N) ➔</text>
          <text x="40" y="110" fill="#94a3b8" font-size="14" font-family="sans-serif">Time / Ops ⬆</text>
          
          <!-- Rough Board Curves -->
          <!-- O(N^2) Curve -->
          <path d="M 100 400 Q 150 380 250 100" stroke="#ef4444" stroke-width="4" fill="none"/>
          <text x="265" y="115" fill="#ef4444" font-weight="bold" font-size="16">O(N²) - Quadratic</text>
          
          <!-- O(N) Curve -->
          <line x1="100" y1="400" x2="550" y2="120" stroke="#f59e0b" stroke-width="3.5"/>
          <text x="565" y="130" fill="#f59e0b" font-weight="bold" font-size="16">O(N) - Linear (Unbalanced BST)</text>
          
          <!-- O(log N) Curve -->
          <path d="M 100 400 Q 300 330 700 300" stroke="#10b981" stroke-width="4" fill="none"/>
          <text x="705" y="295" fill="#10b981" font-weight="bold" font-size="16">O(log N) - Logarithmic (Balanced BST)</text>
          
          <!-- Teacher note box -->
          <rect x="420" y="320" width="340" height="70" fill="#1e293b" rx="6" stroke="#38bdf8"/>
          <text x="435" y="348" fill="#38bdf8" font-size="15" font-weight="bold">Key Takeaway:</text>
          <text x="435" y="372" fill="#e2e8f0" font-size="13">Logarithmic O(log N) growth stays nearly flat even for 1 Million items!</text>
        </svg>`,
        handwrittenNotes: [
          'O(log N) is exponentially faster than linear O(N)',
          'For N = 1,000,000 items: O(N) requires 1 million operations vs O(log N) which takes ~20 operations!',
          'Self-balancing BSTs (AVL / Red-Black) guarantee O(log N) time.'
        ],
        extractedText: 'Big-O Complexity Comparison Graph. Input Size (N) vs Time / Ops. O(N^2) Quadratic, O(N) Linear (Unbalanced BST), O(log N) Logarithmic (Balanced BST). Key Takeaway: Logarithmic O(log N) growth stays flat even for 1 Million items!',
        diagrams: [
          {
            id: 'diag-bigo-graph',
            title: 'Algorithmic Growth Rates Graph',
            type: 'graph',
            roughSketchSvg: `<svg viewBox="0 0 400 300" xmlns="http://www.w3.org/2000/svg">
              <rect width="400" height="300" fill="#18181b" rx="8"/>
              <text x="20" y="25" fill="#ef4444" font-size="12" font-family="monospace">[Teacher's Rough Board Graph]</text>
              <line x1="50" y1="250" x2="350" y2="250" stroke="#71717a" stroke-width="2"/>
              <line x1="50" y1="250" x2="50" y2="50" stroke="#71717a" stroke-width="2"/>
              <path d="M 50 250 Q 80 200 120 50" stroke="#ef4444" stroke-width="2" fill="none"/>
              <line x1="50" y1="250" x2="300" y2="80" stroke="#f59e0b" stroke-width="2"/>
              <path d="M 50 250 Q 180 210 350 190" stroke="#10b981" stroke-width="2" fill="none"/>
            </svg>`,
            cleanDiagramSvg: `<svg viewBox="0 0 400 300" xmlns="http://www.w3.org/2000/svg">
              <rect width="400" height="300" fill="#0f172a" rx="8" stroke="#1e293b"/>
              <text x="20" y="25" fill="#10b981" font-size="14" font-weight="bold" font-family="sans-serif">✓ AI Cleaned-Up Interactive Coordinate Graph</text>
              
              <!-- Grid lines -->
              <line x1="60" y1="200" x2="360" y2="200" stroke="#1e293b" stroke-dasharray="3"/>
              <line x1="60" y1="150" x2="360" y2="150" stroke="#1e293b" stroke-dasharray="3"/>
              <line x1="60" y1="100" x2="360" y2="100" stroke="#1e293b" stroke-dasharray="3"/>
              
              <!-- Axes -->
              <line x1="60" y1="250" x2="370" y2="250" stroke="#64748b" stroke-width="2"/>
              <line x1="60" y1="250" x2="60" y2="40" stroke="#64748b" stroke-width="2"/>
              <text x="360" y="275" fill="#94a3b8" font-size="11" font-family="sans-serif">N (Elements)</text>
              <text x="15" y="45" fill="#94a3b8" font-size="11" font-family="sans-serif">Time</text>
              
              <!-- Curves -->
              <path d="M 60 250 Q 100 220 130 50" stroke="#ef4444" stroke-width="3" fill="none"/>
              <text x="135" y="65" fill="#ef4444" font-size="11" font-weight="bold">O(N²)</text>
              
              <line x1="60" y1="250" x2="300" y2="70" stroke="#f59e0b" stroke-width="3"/>
              <text x="305" y="80" fill="#f59e0b" font-size="11" font-weight="bold">O(N)</text>
              
              <path d="M 60 250 Q 180 205 360 195" stroke="#10b981" stroke-width="3" fill="none"/>
              <text x="280" y="185" fill="#10b981" font-size="11" font-weight="bold">O(log N) ✓</text>
              
              <!-- Highlights -->
              <circle cx="210" cy="200" r="5" fill="#10b981"/>
              <text x="220" y="215" fill="#38bdf8" font-size="10">Balanced BST Target</text>
            </svg>`,
            explanations: {
              en: 'This graph compares how execution time scales as input size (N) grows. O(log N) curve flattens quickly, proving why logarithmic search algorithms remain ultra-fast even for billions of elements.',
              hi: 'यह ग्राफ दिखाता है कि इनपुट का आकार (N) बढ़ने पर समय कैसे बदलता है। O(log N) वक्र तेजी से समतल होता है, जिससे यह साबित होता है कि अरबों तत्वों के लिए भी लॉगरिथमिक सर्च बेहद तेज़ रहती है।',
              bn: 'এই গ্রাফটি দেখায় যে ইনপুটের আকার (N) বৃদ্ধির সাথে সাথে সম্পাদনের সময় কীভাবে পরিবর্তিত হয়। O(log N) কার্ভটি দ্রুত সমতল হয়, যা প্রমাণ করে যে কোটি কোটি এলিমেন্টের জন্যও এই অ্যালগরিদমটি দ্রুত কাজ করে।',
              ar: 'يوضح هذا الرسم البياني كيف يتدرج وقت التنفيذ مع زيادة حجم المدخلات (N). ينبسط منحنى O(log N) بسرعة، مما يثبت أن خوارزميات البحث اللوغاريتمية تظل فائقة السرعة حتى لمليارات العناصر.'
            },
            keyTakeaways: {
              en: [
                'O(1) Constant > O(log N) Logarithmic > O(N) Linear > O(N²) Quadratic',
                'Unbalanced BST degrades to O(N)',
                'AVL & Red-Black trees auto-rebalance to maintain O(log N)'
              ],
              hi: [
                'O(1) स्थिरांक > O(log N) लॉगरिथमिक > O(N) रेखीय > O(N²) द्विघात',
                'असंतुलित BST ओ(N) तक खराब हो जाता है',
                'AVL और रेड-ब्लैक ट्री O(log N) बनाए रखने के लिए ऑटो-रीबैलेंस होते हैं'
              ],
              bn: [
                'O(1) ধ্রুবক > O(log N) লগারিদমিক > O(N) রৈখিক > O(N²) দ্বিঘাত',
                'ভারসাম্যহীন BST ও(N) এ অবনমিত হয়',
                'AVL এবং রেড-ব্ল্যাক ট্রি স্বয়ংক্রিয়ভাবে ভারসাম্য রক্ষা করে O(log N) বজায় রাখে'
              ],
              ar: [
                'O(1) ثابت > O(log N) لوغاريتمي > O(N) خطي > O(N²) تربيعي',
                'تتدهور شجرة BST غير المتوازنة إلى O(N)',
                'تعيد أشجار AVL و Red-Black التوازن تلقائيًا للحفاظ على O(log N)'
              ]
            }
          }
        ],
        formulas: [
          {
            id: 'form-2',
            latex: 'T(N) = T(N/2) + O(1) \\implies T(N) = O(\\log_2 N)',
            description: {
              en: 'Recurrence relation for Binary Search in a balanced BST.',
              hi: 'संतुलित BST में बाइनरी सर्च के लिए पुनरावृत्ति संबंध (Recurrence Relation)।',
              bn: 'ভারসাম্যপূর্ণ BST-তে বাইনারি সার্চের পুনরাবৃত্তি সম্পর্ক।',
              ar: 'علاقة التكرار للبحث الثنائي في شجرة BST متوازنة.'
            },
            variableBreakdown: {
              en: { 'T(N)': 'Total time for N elements', 'T(N/2)': 'Time to search half remaining subtree' },
              hi: { 'T(N)': 'N तत्वों के लिए कुल समय', 'T(N/2)': 'आधे बचे हुए सब-ट्री को खोजने का समय' },
              bn: { 'T(N)': 'N টি উপাদানের জন্য মোট সময়', 'T(N/2)': 'অর্ধেক বাকি সাব-ট্রিতে খোঁজার সময়' },
              ar: { 'T(N)': 'الوقت الإجمالي لـ N من العناصر', 'T(N/2)': 'وقت البحث في نصف الشجرة الفرعية المتبقية' }
            }
          }
        ]
      }
    ],
    transcript: [
      {
        id: 't-1',
        timestamp: '00:30',
        speaker: 'Prof. Turing',
        originalEnglishText: 'Good morning everyone. Today we are diving into Binary Search Trees. Remember, the main principle of a BST is that for any node, all left children are smaller and all right children are larger.',
        translations: {
          en: 'Good morning everyone. Today we are diving into Binary Search Trees. Remember, the main principle of a BST is that for any node, all left children are smaller and all right children are larger.',
          hi: 'सुप्रभात सभी को। आज हम बाइनरी सर्च ट्री के बारे में गहराई से समझेंगे। याद रखें, BST का मुख्य सिद्धांत यह है कि किसी भी नोड के लिए, सभी बाएं मान छोटे और दाएं मान बड़े होते हैं।',
          bn: 'সবাইকে শুভ সকাল। আজ আমরা বাইনারি সার্চ ট্রি সম্পর্কে বিস্তারিত আলোচনা করব। মনে রাখবেন, BST-এর প্রধান নীতি হল যেকোনো নোডের জন্য, সমস্ত বাম চাইল্ড ছোট এবং ডান চাইল্ড বড় হয়।',
          ar: 'صباح الخير جميعا. اليوم نتناول أشجار البحث الثنائية. تذكروا أن المبدأ الأساسي لشجرة BST هو أنه لأي عقدة، تكون جميع العناصر اليسرى أصغر والعناصر اليمنى أكبر.'
        },
        associatedPageId: 'page-1'
      },
      {
        id: 't-2',
        timestamp: '02:45',
        speaker: 'Prof. Turing',
        originalEnglishText: 'As you can see on the whiteboard slide 1, if we look at node 15, left node 10 is smaller, and 25 is larger. The height formula is h = log2(N+1) minus 1.',
        translations: {
          en: 'As you can see on the whiteboard slide 1, if we look at node 15, left node 10 is smaller, and 25 is larger. The height formula is h = log2(N+1) minus 1.',
          hi: 'जैसा कि आप व्हाइटबोर्ड स्लाइड 1 पर देख सकते हैं, नोड 15 में, बायां नोड 10 छोटा है और 25 बड़ा है। ऊंचाई का सूत्र h = log2(N+1) - 1 है।',
          bn: 'যেমনটি আপনারা হোয়াইটবোর্ড স্লাইড ১ এ দেখতে পাচ্ছেন, নোড ১৫ এর জন্য বাম নোড ১০ ছোট এবং ২৫ বড়। উচ্চতার সূত্র হল h = log2(N+1) - 1।',
          ar: 'كما ترون في الشريحة 1، إذا نظرنا إلى العقدة 15، فإن العقدة اليسرى 10 أصغر، و25 أكبر. صيغة الارتفاع هي h = log2(N+1) ناقص 1.'
        },
        associatedPageId: 'page-1'
      },
      {
        id: 't-3',
        timestamp: '14:50',
        speaker: 'Prof. Turing',
        originalEnglishText: 'Now pay close attention to this graph on slide 2! O(log N) is the holy grail of search algorithms. Notice how flat the green curve stays even when N reaches 1 Million items.',
        translations: {
          en: 'Now pay close attention to this graph on slide 2! O(log N) is the holy grail of search algorithms. Notice how flat the green curve stays even when N reaches 1 Million items.',
          hi: 'अब स्लाइड 2 पर इस ग्राफ पर ध्यान दें! O(log N) सर्च एल्गोरिदम का सबसे सर्वश्रेष्ठ लक्ष्य है। देखें कि 10 लाख (1 Million) आइटम्स होने पर भी हरी रेखा कितनी समतल रहती है।',
          bn: 'এখন স্লাইড ২-এর এই গ্রাফটিতে ভালো করে লক্ষ্য করুন! O(log N) হল সার্চ অ্যালগরিদমের সেরা ফলাফল। দেখুন কিভাবে সবুজ রেখাটি ১০ লক্ষ আইটেম থাকলেও সমতল থাকে।',
          ar: 'الآن انتبهوا جيدًا لهذا الرسم البياني في الشريحة 2! O(log N) هو الهدف الأسمى لخوارزميات البحث. لاحظ كيف يظل المنحنى الأخضر مسطحًا حتى عندما تصل N إلى مليون عنصر.'
        },
        associatedPageId: 'page-2'
      }
    ],
    notes: {
      title: {
        en: 'Structured Classroom Notes: Binary Search Trees & Complexity Analysis',
        hi: 'संरचित कक्षा नोट्स: बाइनरी सर्च ट्री और जटिलता विश्लेषण',
        bn: 'সুসংগঠিত ক্লাস নোট: বাইনারি সার্চ ট্রি এবং কমপ্লেক্সিটি বিশ্লেষণ',
        ar: 'ملاحظات الفصل المنظمة: أشجار البحث الثنائية وتحليل التعقيد'
      },
      lectureOverview: {
        en: 'This lecture covered the foundational mathematical & structural properties of Binary Search Trees (BST), focusing on node placement rules, tree height calculations, and Big-O efficiency curves.',
        hi: 'इस व्याख्यान में बाइनरी सर्च ट्री (BST) के बुनियादी गणितीय और संरचनात्मक गुणों को शामिल किया गया, जिसमें नोड नियम, ऊंचाई की गणना और बिग-ओ दक्षता ग्राफ पर ध्यान केंद्रित किया गया।',
        bn: 'এই লেকচারে বাইনারি সার্চ ট্রি (BST)-এর মৌলিক গাণিতিক ও কাঠামোগত বৈশিষ্ট্য, নোডের নিয়মাবলী, ট্রির উচ্চতা গণনা এবং Big-O দক্ষতা আলোচনা করা হয়েছে।',
        ar: 'غطت هذه المحاضرة الخصائص الرياضية والهيكلية الأساسية لأشجار البحث الثنائية (BST)، مع التركيز على قواعد وضع العقد، وحسابات ارتفاع الشجرة، ومنحنيات كفاءة Big-O.'
      },
      keyConcepts: {
        en: [
          { concept: 'BST Node Property', explanation: 'Left child < Root < Right child for every node sub-tree.' },
          { concept: 'Logarithmic Search Time', explanation: 'Balanced BST reduces operations by cutting search space in half at each step.' },
          { concept: 'Degeneracy Risk', explanation: 'An unbalanced tree becomes a linked list with worst-case O(N) complexity.' }
        ],
        hi: [
          { concept: 'BST नोड गुण', explanation: 'प्रत्येक नोड सब-ट्री के लिए बायां चाइल्ड < रूट < दायां चाइल्ड।' },
          { concept: 'लॉगरिथमिक खोज समय', explanation: 'संतुलित BST प्रत्येक चरण में खोज क्षेत्र को आधा करके संचालन को कम करता है।' },
          { concept: 'अपघटन (Degeneracy) का जोखिम', explanation: 'एक असंतुलित ट्री एक लिंक्ड लिस्ट बन जाता है जिसकी सबसे खराब स्थिति O(N) होती है।' }
        ],
        bn: [
          { concept: 'BST নোডের বৈশিষ্ট্য', explanation: 'প্রতিটি নোডের জন্য বাম চাইল্ড < রুট < ডান চাইল্ড।' },
          { concept: 'লগারিদমিক সার্চ টাইম', explanation: 'ভারসাম্যপূর্ণ BST প্রতি পদক্ষেপে অনুসন্ধানের পরিধি অর্ধেক করে ফেলে।' },
          { concept: 'ডিজেনারেসি ঝুঁকি', explanation: 'একটি ভারসাম্যহীন ট্রি লিঙ্কড লিস্টে পরিণত হয় যার সবচেয়ে খারাপ জটিলতা O(N)।' }
        ],
        ar: [
          { concept: 'خاصية عقدة BST', explanation: 'العقدة الفرعية اليسرى < العقدة الأصلية < العقدة الفرعية اليمنى لكل عقدة.' },
          { concept: 'وقت البحث اللوغاريتمي', explanation: 'تقلل شجرة BST المتوازنة العمليات عن طريق تقليل مساحة البحث إلى النصف في كل خطوة.' },
          { concept: 'مخاطر التدهور', explanation: 'تتحول الشجرة غير المتوازنة إلى قائمة مرتبطة ذات تعقيد O(N) في أسوأ الحالات.' }
        ]
      },
      simplifiedSummary: {
        en: 'In simple words: A Binary Search Tree is like a smart phone directory split in half at every step. Instead of checking 1,000,000 pages one by one, you only need ~20 page flips to find any record!',
        hi: 'सरल शब्दों में: बाइनरी सर्च ट्री एक स्मार्ट टेलीफोन डायरेक्टरी की तरह है जिसे हर कदम पर आधा कर दिया जाता है। 10,00,000 पेजों को एक-एक करके जांचने के बजाय, आपको केवल 20 पेजों को पलटने की आवश्यकता होती है!',
        bn: 'সহজ কথায়: বাইনারি সার্চ ট্রি হল একটি স্মার্ট ডিজিটাল ডিরেক্টরির মতো যা প্রতিটি ধাপে অর্ধেক হয়ে যায়। ১০,০০,০০০ পৃষ্ঠা একে একে দেখার বদলে মাত্র ২০টি পদক্ষেপে যেকোনো তথ্য খুঁজে পাওয়া যায়!',
        ar: 'بكلمات بسيطة: شجرة البحث الثنائية تشبه دليل هاتف ذكي يتم تقليصه إلى النصف في كل خطوة. بدلاً من فحص 1,000,000 صفحة واحدة تلو الأخرى، تحتاج فقط إلى ~20 تقليباً للعثور على أي سجل!'
      },
      technicalTerms: {
        en: [
          { term: 'Binary Search Tree (BST)', definition: 'A node-based binary tree data structure with strict ordering properties.' },
          { term: 'Height (h)', definition: 'Length of the longest downward path from root node to a leaf node.' },
          { term: 'Big-O Notation O(log N)', definition: 'Mathematical measurement of algorithm execution scaling.' }
        ],
        hi: [
          { term: 'बाइनरी सर्च ट्री (BST)', definition: 'सख्त क्रम नियमों वाला नोड-आधारित डेटा स्ट्रक्चर।' },
          { term: 'ऊंचाई (Height - h)', definition: 'रूट नोड से लीफ नोड तक सबसे लंबे रास्ते की लंबाई।' },
          { term: 'बिग-ओ नोटेशन O(log N)', definition: 'एल्गोरिदम निष्पादन गति का गणितीय माप।' }
        ],
        bn: [
          { term: 'বাইনারি সার্চ ট্রি (BST)', definition: 'নির্দিষ্ট নিয়ম অনুসৃত নোড-ভিত্তিক ডেটা স্ট্রাকচার।' },
          { term: 'উচ্চতা (Height - h)', definition: 'রুট নোড থেকে দীর্ঘতম নিচের দিকের পথের দৈর্ঘ্য।' },
          { term: 'Big-O সংকেত O(log N)', definition: 'অ্যালগরিদমের কার্যক্ষমতা বৃদ্ধির গাণিতিক পরিমাপ।' }
        ],
        ar: [
          { term: 'شجرة البحث الثنائية (BST)', definition: 'هيكل بيانات ثنائي قائم على العقد مع خصائص ترتيب صارمة.' },
          { term: 'الارتفاع (h)', definition: 'طول أطول مسار تنازلي من العقدة الجذرية إلى العقدة الورقية.' },
          { term: 'ترميز Big-O O(log N)', definition: 'قياس رياضي لتوسع وقت تنفيذ الخوارزمية.' }
        ]
      }
    }
  }
];
