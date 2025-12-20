/** @type {import('tailwindcss').Config} */
export default {
    content: [
        "./index.html",
        "./src/**/*.{js,ts,jsx,tsx}",
    ],
    theme: {
        extend: {
            colors: {
                primary: "#FF8D28",
                surface: "#121212",
                "surface-glass": "rgba(28, 28, 30, 0.6)",
            },
            fontFamily: {
                sans: ['Inter', 'sans-serif'],
                display: ['SF Pro Display', '-apple-system', 'BlinkMacSystemFont', 'sans-serif'],
                logo: ['SF Pro Display', '-apple-system', 'BlinkMacSystemFont', 'sans-serif'],
            },
            animation: {
                'fade-in-up': 'fadeInUp 0.8s cubic-bezier(0.165, 0.84, 0.44, 1) forwards',
            },
            keyframes: {
                fadeInUp: {
                    '0%': { opacity: '0', transform: 'translateY(20px)' },
                    '100%': { opacity: '1', transform: 'translateY(0)' },
                }
            }
        },
    },
    plugins: [],
}
