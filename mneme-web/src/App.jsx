import { BrowserRouter as Router, Routes, Route, useLocation } from 'react-router-dom'
import { useEffect } from 'react'
import Home from './pages/Home'
import Privacy from './pages/Privacy'
import Support from './pages/Support'

function ScrollToTop() {
    const { pathname } = useLocation()

    useEffect(() => {
        window.scrollTo(0, 0)
    }, [pathname])

    return null
}

function App() {
    return (
        <Router>
            <ScrollToTop />
            <div className="min-h-screen bg-black text-white selection:bg-primary selection:text-white">
                <div className="fixed inset-0 bg-[radial-gradient(circle_at_50%_0%,rgba(255,141,40,0.15),transparent_70%)] pointer-events-none" />
                <Routes>
                    <Route path="/" element={<Home />} />
                    <Route path="/privacy" element={<Privacy />} />
                    <Route path="/support" element={<Support />} />
                </Routes>
            </div>
        </Router>
    )
}

export default App
